#!/usr/bin/env python3
"""folke.py - simpel selfhostet søvnforudsigelse oven på Baby Buddy.

Henter søvnlog fra Baby Buddy, beregner næste lur/sengetid og
- opdaterer sensor.baby_next_sleep i Home Assistant
- sender en notifikation LEAD_MIN minutter før, og en til, hvis tiden er overskredet med OVERDUE_MIN
  (hver kun én gang pr. forudsigelse)

Kun standardbibliotek (Python 3.11+). Kør fx hvert 5. minut.
"""
import json
import os
import statistics
import urllib.request
from datetime import datetime, timedelta, date
from zoneinfo import ZoneInfo

BB_URL = os.environ.get("BB_URL", "http://localhost:8000").rstrip("/")
BB_TOKEN = os.environ.get("BB_TOKEN", "")
HA_URL = os.environ.get("HA_URL", "").rstrip("/")
HA_TOKEN = os.environ.get("HA_TOKEN", "")
HA_NOTIFY = os.environ.get("HA_NOTIFY", "")  # fx notify.mobile_app_min_telefon
HA_SENSOR = os.environ.get("HA_SENSOR", "sensor.baby_next_sleep")
# Beskedtyper, Home Assistant får (udpumpning kun, hvis man selv tilføjer "pump")
HA_KINDS = os.environ.get("HA_KINDS", "sleep_soon,overdue").replace(" ", "").split(",")
CHILD_ID = os.environ.get("CHILD_ID")
LEAD_MIN = int(os.environ.get("LEAD_MIN", "30"))
OVERDUE_MIN = int(os.environ.get("OVERDUE_MIN", "15"))
HISTORY_DAYS = int(os.environ.get("HISTORY_DAYS", "10"))
DEFAULT_BEDTIME = int(os.environ.get("DEFAULT_BEDTIME_MIN", str(19 * 60 + 30)))
STATE_FILE = os.environ.get("STATE_FILE", "/data/state.json")
TZ = ZoneInfo(os.environ.get("TZ", "Europe/Copenhagen"))


# ---------- HTTP ----------
def call(url, token, method="GET", body=None, scheme="Token"):
    req = urllib.request.Request(
        url,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"{scheme} {token}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        raw = r.read()
        return json.loads(raw) if raw else None


def bb_all(path):
    url = f"{BB_URL}/api/{path}"
    out = []
    while url:
        page = call(url, BB_TOKEN)
        out += page["results"]
        url = page.get("next")
    return out


# ---------- Forudsigelse ----------
def default_window(age_days):
    """Groft vågenvindue (minutter) efter alder - bruges kun til der er data nok."""
    months = age_days / 30.4
    for limit, mins in [(2, 60), (3, 75), (4, 90), (6, 120), (9, 150), (12, 180), (18, 210)]:
        if months < limit:
            return mins
    return 270


def predict(sleeps, birth_date, now):
    """sleeps: liste af dicts med id, start, end (datetime), nap (bool)."""
    sleeps = sorted(sleeps, key=lambda s: s["start"])
    if not sleeps:
        return None

    # Vågenvinduer pr. position på dagen (0 = morgen, 1 = efter 1. lur ...)
    windows = {}
    all_gaps = []
    pos = 0
    for prev, nxt in zip(sleeps, sleeps[1:]):
        pos = 0 if not prev["nap"] else pos + 1
        gap = (nxt["start"] - prev["end"]).total_seconds() / 60
        if 20 < gap < 480:
            windows.setdefault(pos, []).append(gap)
            all_gaps.append(gap)

    # Position for den næste søvn
    last = sleeps[-1]
    pos = 0
    for s in sleeps:
        pos = 0 if not s["nap"] else pos + 1

    age_days = (now.date() - birth_date).days
    samples = windows.get(pos, [])[-7:]
    # basis (til UI'et): own = eget vindue for netop denne position, all = alle vinduer, age = alder
    if len(samples) >= 3:
        window, source, basis = statistics.median(samples), f"eget mønster (position {pos})", "own"
    elif len(all_gaps) >= 5:
        window, source, basis = statistics.median(all_gaps[-15:]), "gennemsnit af alle vinduer", "all"
    else:
        window, source, basis = default_window(age_days), "aldersbaseret standard", "age"

    next_start = last["end"] + timedelta(minutes=window)

    # Typisk sengetid = median af aftensøvne (kl. 17-24)
    evenings = [
        s["start"].hour * 60 + s["start"].minute
        for s in sleeps
        if not s["nap"] and s["start"].hour >= 17
    ]
    bed_min = int(statistics.median(evenings)) if len(evenings) >= 3 else DEFAULT_BEDTIME
    bed = next_start.replace(hour=bed_min // 60, minute=bed_min % 60, second=0, microsecond=0)

    if next_start >= bed - timedelta(minutes=60):
        # Er sengetiden allerede gået (sent på aftenen), er det sengetid, så snart vinduet er gået
        kind, when = "sengetid", max(bed, next_start)
    else:
        kind, when = "lur", next_start

    return {
        "kind": kind,
        "time": when,
        "window_min": round(window),
        "source": source,
        "basis": basis,
        "pos": pos,  # 0 = efter natten, 1 = efter 1. lur ...
        "bed_basis": "own" if len(evenings) >= 3 else "default",
        "last_id": last["id"],
    }


# ---------- Home Assistant ----------
def ha_update(pred):
    body = {
        "state": pred["time"].isoformat(),
        "attributes": {
            "device_class": "timestamp",
            "friendly_name": "Næste søvn",
            "kind": pred["kind"],
            "window_min": pred["window_min"],
            "source": pred["source"],
        },
    }
    call(f"{HA_URL}/api/states/{HA_SENSOR}", HA_TOKEN, "POST", body, scheme="Bearer")


# Ekstra notifikationskanal ud over Home Assistant (web push), sat af app.py: objekt med active() og send()
push = None
# Barnets visningsnavn (sat af app.py fra prefs.json), ellers navnet fra databasen
display_name = None

# Beskedtyper, som hver enhed kan slå til og fra (push.json). Home Assistant får dem i HA_KINDS.
KINDS = ("sleep_soon", "overdue", "pump")


def _ha(kind):
    return bool(HA_URL and HA_NOTIFY) and (kind is None or kind in HA_KINDS)


def can_notify(kind=None):
    """Er der nogen, der vil have denne beskedtype (eller nogen besked overhovedet)?"""
    return _ha(kind) or bool(push and push.active(kind))


def notify(title, msg, kind=None):
    """Send via alle kanaler, der vil have beskedtypen. En fejl i den ene stopper ikke den anden."""
    if _ha(kind):
        try:
            path = HA_NOTIFY.replace(".", "/", 1)
            call(f"{HA_URL}/api/services/{path}", HA_TOKEN, "POST",
                 {"title": title, "message": msg}, scheme="Bearer")
        except Exception as e:
            print("notify ha:", e, flush=True)
    if push and push.active(kind):
        try:
            push.send(title, msg, kind=kind)
        except Exception as e:
            print("notify push:", e, flush=True)


def soon_text(pred):
    t = f"{pred['time'].astimezone(TZ):%H:%M}"
    return f"Tid til at slappe af. {'Næste lur' if pred['kind'] == 'lur' else 'Sengetid'} ca. kl. {t}"


def overdue_text(pred, name):
    what = "en lur" if pred["kind"] == "lur" else "at putte til natten"
    return f"{name or 'Babyen'} virker meget frisk. Prøv alligevel {what}"


def load_state():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_state(state):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)


# ---------- Main ----------
def parse(s):
    return datetime.fromisoformat(s).astimezone(TZ)


def main():
    import store  # her og ikke øverst: store importerer folke

    db = store.get()
    now = datetime.now(TZ)
    child = db.child()
    if not child:
        raise SystemExit("Intet barn fundet")
    birth = date.fromisoformat(child["birth_date"])

    raw = db.sleeps(child["id"], now - timedelta(days=HISTORY_DAYS))
    sleeps = [
        {"id": s["id"], "start": parse(s["start"]), "end": parse(s["end"]), "nap": s["nap"]}
        for s in raw
    ]

    pred = predict(sleeps, birth, now)
    if not pred:
        print("Ingen søvndata endnu")
        return
    print(f"Næste {pred['kind']}: {pred['time']:%a %H:%M} "
          f"(vindue {pred['window_min']} min, {pred['source']})")

    if HA_URL:
        ha_update(pred)

    # Notifikationer: LEAD_MIN før ("slap af") og OVERDUE_MIN efter ("virker frisk"),
    # hver kun én gang pr. forudsigelse, og ikke hvis søvnen allerede er startet
    until = (pred["time"] - now).total_seconds() / 60
    soon = 0 <= until <= LEAD_MIN
    late = -120 <= until <= -OVERDUE_MIN  # ikke flere timer efter, fx hvis appen har været nede
    if not (soon or late) or not can_notify("sleep_soon" if soon else "overdue"):
        return
    try:
        if db.timer(child["id"]):
            return
    except Exception:
        pass
    state = load_state()
    key = "notified" if soon else "overdue"
    if state.get(key) == pred["last_id"]:
        return
    if soon:
        notify("Søvn", soon_text(pred), kind="sleep_soon")
    else:
        name = (display_name and display_name()) or child.get("first_name")
        notify("Søvn", overdue_text(pred, name), kind="overdue")
    state[key] = pred["last_id"]
    save_state(state)


if __name__ == "__main__":
    main()
