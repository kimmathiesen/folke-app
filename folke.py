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


def default_naps(age_days):
    """Typisk antal lure om dagen efter alder - bruges kun til der er data nok."""
    months = age_days / 30.4
    for limit, n in [(4, 4), (7, 3), (15, 2)]:
        if months < limit:
            return n
    return 1


SHORT_NAP = 30          # lure under 30 min er «uventede» (fx i barnevognen) og tæller ikke som en af dagens lure
SHORT_FACTOR = 0.75     # vinduet efter en kort lur er 75 % af det normale
OUTLIER = (0.6, 1.6)    # vinduer uden for 60-160 % af hans median (fx dage med misset lur) tæller ikke med
MAX_BED_SHIFT = 60      # sengetiden rykkes højst 60 min frem efter en dag med for lidt søvn
DEFAULT_NAP_LEN = 60    # lurlængde, til der er data nok


def _mins(a, b):
    return (b - a).total_seconds() / 60


def _short(s):
    return s["nap"] and _mins(s["start"], s["end"]) < SHORT_NAP


def _robust(samples, n):
    """De sidste n prøver, uden afvigere (hvis der er nok til at se, hvad der er normalt)."""
    if len(samples) >= 4:
        m = statistics.median(samples)
        samples = [x for x in samples if OUTLIER[0] * m <= x <= OUTLIER[1] * m]
    return samples[-n:]


class _Model:
    """Hans egne tal, lært af historikken. Korte lure tæller ikke som lure, og vinduerne
    lige før og efter dem bruges ikke, så en enkelt skæv dag ikke ændrer de normale tal."""

    def __init__(self, sleeps, age_days):
        self.age_days = age_days
        self.windows, self.all_gaps, self.lengths, self.all_lengths = {}, [], {}, []
        self.naps_per_day, self.evenings = [], []
        pos = k = 0
        night_seen = False
        for i, s in enumerate(sleeps):
            if not s["nap"]:
                if night_seen:
                    self.naps_per_day.append(k)  # en hel dag mellem to nætter
                night_seen, pos, k = True, 0, 0
                if s["start"].hour >= 17:
                    self.evenings.append(s["start"].hour * 60 + s["start"].minute)
            elif not _short(s):
                k += 1
                d = _mins(s["start"], s["end"])
                self.lengths.setdefault(k, []).append(d)
                self.all_lengths.append(d)
            if i + 1 < len(sleeps):
                nxt = sleeps[i + 1]
                if s["nap"] and not _short(s):
                    pos += 1
                if _short(s) or _short(nxt):
                    continue
                gap = _mins(s["end"], nxt["start"])
                if 20 < gap < 480:
                    self.windows.setdefault(pos, []).append(gap)
                    self.all_gaps.append(gap)

    def window(self, pos):
        """(minutter, kilde, basis) for vinduet efter natten (pos 0) eller efter pos. lur."""
        own = _robust(self.windows.get(pos, []), 7)
        if len(own) >= 3:
            return statistics.median(own), f"eget mønster (position {pos})", "own"
        every = _robust(self.all_gaps, 15)
        if len(every) >= 5:
            return statistics.median(every), "gennemsnit af alle vinduer", "all"
        return default_window(self.age_days), "aldersbaseret standard", "age"

    def nap_length(self, k):
        own = _robust(self.lengths.get(k, []), 7)
        if len(own) >= 3:
            return statistics.median(own)
        every = _robust(self.all_lengths, 15)
        return statistics.median(every) if len(every) >= 3 else DEFAULT_NAP_LEN

    def naps(self):
        days = self.naps_per_day[-7:]
        return round(statistics.median(days)) if len(days) >= 3 else default_naps(self.age_days)

    def bed_min(self):
        return int(statistics.median(self.evenings)) if len(self.evenings) >= 3 else DEFAULT_BEDTIME


def plan_day(sleeps, birth_date, now, running=None, replan=True):
    """Plan for resten af dagen: kommende lure og sengetid, ud fra hans egne tal.

    sleeps: afsluttede søvn (dicts med id, start, end, nap). running: starttidspunkt for en lur, der er
    i gang (nattesøvn i gang giver ingen plan). Genberegnes hver gang:
    - efter en kort lur (under 30 min) er næste vindue 75 % af det normale, og den kortere lur tæller ikke
      som en af dagens lure
    - har dagen givet mindre søvn end normalt, rykkes sengetiden halvdelen af underskuddet frem (højst 60 min)
    - replan=True: er han stadig vågen OVERDUE_MIN efter planlagt lur, er næste lur «nu», og resten af dagen
      flyttes. (Beskederne bruger replan=False, så «virker meget frisk» kommer på det oprindelige tidspunkt.)
    """
    sleeps = sorted(sleeps, key=lambda s: s["start"])
    if not sleeps:
        return None
    m = _Model(sleeps, (now.date() - birth_date).days)
    last = sleeps[-1]

    # Dagen indtil nu: lure siden sidste nat (korte tæller med i søvnen, men ikke som lure)
    today = []
    for s in reversed(sleeps):
        if not s["nap"]:
            break
        today.insert(0, s)
    k = sum(1 for s in today if not _short(s))
    slept = sum(_mins(s["start"], s["end"]) for s in today)
    pos = k  # position for næste vindue: 0 = efter natten, 1 = efter 1. lur ...

    win, source, basis = m.window(pos)
    short = round(_mins(last["start"], last["end"])) if _short(last) else None
    if short is not None:
        win *= SHORT_FACTOR
    wake, t = last["end"], last["end"] + timedelta(minutes=win)
    first_win, first_pos, wake_at = win, pos, None

    if running is not None:  # en lur er i gang: planen regnes fra forventet opvågning
        length = m.nap_length(k + 1)
        wake = max(running + timedelta(minutes=length), now)
        wake_at, k, pos, slept = wake, k + 1, pos + 1, slept + _mins(running, wake)
        win, source, basis = m.window(pos)
        t, first_win, first_pos = wake + timedelta(minutes=win), win, pos

    bed_min = m.bed_min()

    def bed_on(x):
        return x.replace(hour=bed_min // 60, minute=bed_min % 60, second=0, microsecond=0)

    missed_at = None
    if (replan and running is None and now > t + timedelta(minutes=OVERDUE_MIN)
            and t < bed_on(t) - timedelta(minutes=60)):
        missed_at, t = t, now  # den planlagte lur blev ikke til noget: prøv nu

    items, dropped = [], False
    for _ in range(6):
        if t >= bed_on(t) - timedelta(minutes=60):
            break
        length = m.nap_length(k + 1)
        end = t + timedelta(minutes=length)
        if end + timedelta(minutes=m.window(pos + 1)[0]) > bed_on(t) + timedelta(minutes=30):
            dropped = True  # ingen plads til luren og hans normale vindue bagefter: tidlig sengetid i stedet
            break
        items.append({"kind": "lur", "start": t, "end": end})
        k, pos, slept, wake = k + 1, pos + 1, slept + length, end
        win = m.window(pos)[0]
        t = end + timedelta(minutes=win)

    # Sengetid: typisk tidspunkt, rykket frem, hvis dagen har givet for lidt søvn. Er en lur droppet,
    # fordi den ikke kunne nås, er det sengetid, når vinduet er gået, dog højst MAX_BED_SHIFT før normalt.
    normal = sum(m.nap_length(i) for i in range(1, m.naps() + 1))
    shift = round(min(MAX_BED_SHIFT, max(0, (normal - slept) / 2)))
    floor = t if not shift else wake + timedelta(minutes=win * SHORT_FACTOR)
    if dropped:
        shift, floor = MAX_BED_SHIFT, t
    if missed_at:
        floor = max(floor, now)
    bedtime = max(bed_on(t) - timedelta(minutes=shift), floor)
    shift = max(0, round(_mins(bedtime, bed_on(t))))
    items.append({"kind": "sengetid", "start": bedtime})

    return {
        "items": items,
        "wake": wake_at,           # forventet opvågning, hvis en lur er i gang
        "missed_at": missed_at,    # oprindeligt planlagt tidspunkt, hvis luren blev sprunget over
        "short": short,            # længden af en kort lur lige før (min)
        "bed_shift": shift,        # minutter sengetiden er rykket frem
        "first_window": round(first_win),
        "source": source,
        "basis": basis,
        "pos": first_pos,
        "bed_basis": "own" if len(m.evenings) >= 3 else "default",
        "naps": m.naps(),
        "last_id": last["id"],
    }


def predict(sleeps, birth_date, now):
    """Næste søvn = første punkt i dagsplanen (uden genberegning ved misset lur).
    sleeps: liste af dicts med id, start, end (datetime), nap (bool)."""
    plan = plan_day(sleeps, birth_date, now, replan=False)
    if not plan:
        return None
    first = plan["items"][0]
    return {
        "kind": first["kind"],
        "time": first["start"],
        "window_min": plan["first_window"],
        "source": plan["source"],
        "basis": plan["basis"],
        "pos": plan["pos"],  # 0 = efter natten, 1 = efter 1. lur ...
        "bed_basis": plan["bed_basis"],
        "short": plan["short"],
        "bed_shift": plan["bed_shift"],
        "last_id": plan["last_id"],
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
