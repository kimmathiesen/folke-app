#!/usr/bin/env python3
"""napper.py - simpel selfhostet søvnforudsigelse oven på Baby Buddy.

Henter søvnlog fra Baby Buddy, beregner næste lur/sengetid og
- opdaterer sensor.baby_next_sleep i Home Assistant
- sender en notifikation LEAD_MIN minutter før (én gang pr. forudsigelse)

Kun standardbibliotek (Python 3.11+). Kør fx hvert 5. minut.
"""
import json
import os
import statistics
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, date
from zoneinfo import ZoneInfo

BB_URL = os.environ.get("BB_URL", "http://localhost:8000").rstrip("/")
BB_TOKEN = os.environ.get("BB_TOKEN", "")
HA_URL = os.environ.get("HA_URL", "").rstrip("/")
HA_TOKEN = os.environ.get("HA_TOKEN", "")
HA_NOTIFY = os.environ.get("HA_NOTIFY", "")  # fx notify.mobile_app_min_telefon
CHILD_ID = os.environ.get("CHILD_ID")
LEAD_MIN = int(os.environ.get("LEAD_MIN", "10"))
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
    if len(samples) >= 3:
        window, source = statistics.median(samples), f"eget mønster (position {pos})"
    elif len(all_gaps) >= 5:
        window, source = statistics.median(all_gaps[-15:]), "gennemsnit af alle vinduer"
    else:
        window, source = default_window(age_days), "aldersbaseret standard"

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
        kind, when = "sengetid", bed
    else:
        kind, when = "lur", next_start

    return {
        "kind": kind,
        "time": when,
        "window_min": round(window),
        "source": source,
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
    call(f"{HA_URL}/api/states/sensor.baby_next_sleep", HA_TOKEN, "POST", body, scheme="Bearer")


def ha_notify(pred):
    path = HA_NOTIFY.replace(".", "/", 1)
    msg = f"Næste {pred['kind']} ca. kl. {pred['time'].astimezone(TZ):%H:%M}"
    call(f"{HA_URL}/api/services/{path}", HA_TOKEN, "POST",
         {"title": "Søvn", "message": msg}, scheme="Bearer")


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
    now = datetime.now(TZ)
    children = bb_all("children/")
    child = next((c for c in children if not CHILD_ID or str(c["id"]) == CHILD_ID), None)
    if not child:
        raise SystemExit("Intet barn fundet i Baby Buddy")
    birth = date.fromisoformat(child["birth_date"])

    since = (now - timedelta(days=HISTORY_DAYS)).isoformat()
    raw = bb_all(f"sleep/?child={child['id']}&start_min={urllib.parse.quote(since)}&limit=200")
    sleeps = [
        {"id": s["id"], "start": parse(s["start"]), "end": parse(s["end"]), "nap": s["nap"]}
        for s in raw if s.get("end")
    ]

    pred = predict(sleeps, birth, now)
    if not pred:
        print("Ingen søvndata endnu")
        return
    print(f"Næste {pred['kind']}: {pred['time']:%a %H:%M} "
          f"(vindue {pred['window_min']} min, {pred['source']})")

    if not HA_URL:
        return
    ha_update(pred)

    # Notifikation: kun i tidsvinduet, kun én gang, ikke hvis en timer kører
    until = (pred["time"] - now).total_seconds() / 60
    if not HA_NOTIFY or not (0 <= until <= LEAD_MIN):
        return
    try:
        timers = bb_all(f"timers/?child={child['id']}")
        if any(t.get("active") for t in timers):
            return
    except Exception:
        pass
    state = load_state()
    if state.get("notified") != pred["last_id"]:
        ha_notify(pred)
        state["notified"] = pred["last_id"]
        save_state(state)


if __name__ == "__main__":
    main()
