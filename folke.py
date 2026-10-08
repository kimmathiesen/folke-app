#!/usr/bin/env python3
"""folke.py - motoren: forudsigelse og dagsplan ud fra søvnloggen.

Henter søvnloggen fra databasen (store.py), beregner næste lur/sengetid og sender web push (push.py)
LEAD_MIN minutter før og en til, hvis tiden er overskredet med OVERDUE_MIN. Hver enhed kan vælge sine
egne minutter, og hver besked sendes kun én gang pr. forudsigelse og enhed. Kaldes hvert minut af app.py.
"""
import json
import os
import statistics
from datetime import datetime, timedelta, date
from zoneinfo import ZoneInfo

CHILD_ID = os.environ.get("CHILD_ID")
LEAD_MIN = int(os.environ.get("LEAD_MIN", "30"))
OVERDUE_MIN = int(os.environ.get("OVERDUE_MIN", "15"))
HISTORY_DAYS = int(os.environ.get("HISTORY_DAYS", "10"))
DEFAULT_BEDTIME = int(os.environ.get("DEFAULT_BEDTIME_MIN", str(19 * 60 + 30)))
STATE_FILE = os.environ.get("STATE_FILE", "/data/state.json")
TZ = ZoneInfo(os.environ.get("TZ", "Europe/Copenhagen"))


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
MAX_BED_SHIFT = 60      # sengetiden rykkes højst 60 min frem (lært rykning, eller lur der ikke kan nås uden aftenlur)
DEFAULT_NAP_LEN = 60    # lurlængde, til der er data nok
CATNAP_FROM = 17 * 60   # en dags sidste lur, der starter kl. 17 eller senere, er en aftenlur
DEFAULT_CATNAP_LEN = 45 # aftenlurens længde, til der er data nok
NIGHT_MIN = 120         # en «nat» under 2 timer, der slutter samme dag, er en aftenlur (fx registreret efter kl. 18)
DEFICIT = 30            # en dag med mindst 30 min mindre dagsøvn end normalt
LEARN_DAYS = 3          # så mange dage med underskud (af de seneste 10), før en rykning af sengetiden læres
MAX_DAY_HOURS = 36      # en «dag» mellem to nætter over 36 timer betyder, at en nat ikke er registreret


def _mins(a, b):
    return (b - a).total_seconds() / 60


def _clock(t):
    """Minutter efter midnat."""
    return t.hour * 60 + t.minute


def _short(s):
    return s["nap"] and _mins(s["start"], s["end"]) < SHORT_NAP


def nap_at_stop(start, end):
    """Gæt på lur eller nat, når en søvn stoppes uden at brugeren har valgt: som `nap_guess` ved start, men en
    «nat» under 2 timer, der slutter samme dag, er en aftenlur (fx 18:23-19:10)."""
    if not (start.hour >= 18 or start.hour < 5):
        return True
    return _mins(start, end) < NIGHT_MIN and end.date() == start.date()


def _normalize(s):
    """Tidligere registreringer: en kort «nat», der sluttede samme aften, læses som lur."""
    if not s["nap"] and _mins(s["start"], s["end"]) < NIGHT_MIN and s["end"].date() == s["start"].date():
        return {**s, "nap": True}
    return s


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
        # Hele dage mellem to nætter: (dagsøvn, natten starter, sidste søvn før natten, aftenlur eller None)
        self.days = []
        pos = k = 0
        night = None
        day = []
        for i, s in enumerate(sleeps):
            if not s["nap"]:
                if night is not None and _mins(night["end"], s["start"]) < MAX_DAY_HOURS * 60:
                    self.naps_per_day.append(k)  # en hel dag mellem to nætter
                    last_nap = next((x for x in reversed(day) if not _short(x)), None)
                    catnap = last_nap if last_nap and _clock(last_nap["start"]) >= CATNAP_FROM else None
                    self.days.append((sum(_mins(x["start"], x["end"]) for x in day), s["start"],
                                      day[-1]["end"] if day else night["end"], catnap))
                night, pos, k, day = s, 0, 0, []
                if s["start"].hour >= 17:
                    self.evenings.append(_clock(s["start"]))
            else:
                day.append(s)
            if s["nap"] and not _short(s):
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

    def catnap_habit(self):
        """Plejer han at tage en aftenlur? Mindst 3 af de seneste 7 hele dage, og mindst halvdelen."""
        days = self.days[-7:]
        n = sum(1 for d in days if d[3])
        return n >= 3 and 2 * n >= len(days)

    def catnap_length(self):
        own = _robust([_mins(d[3]["start"], d[3]["end"]) for d in self.days if d[3]], 7)
        return statistics.median(own) if own else DEFAULT_CATNAP_LEN

    def evening_gap(self):
        """Hvor længe han typisk er vågen efter dagens sidste søvn, før natten starter (None uden data)."""
        own = _robust([_mins(d[2], d[1]) for d in self.days if d[3]], 7)
        return statistics.median(own) if len(own) >= 3 else None

    def normal_day_sleep(self):
        """Normal dagsøvn i minutter: median af de hele dage, ellers summen af hans normale lurlængder."""
        days = [d[0] for d in self.days[-7:]]
        if len(days) >= 3:
            return statistics.median(days)
        return sum(self.nap_length(i) for i in range(1, self.naps() + 1))

    def learned_shift(self):
        """Minutter, han plejer at falde i søvn tidligere efter en dag med for lidt dagsøvn. 0, til hans egne
        data viser det: mindst LEARN_DAYS dage med underskud og en median på mindst 15 min tidligere end normalt."""
        if len(self.days) < 3:
            return 0
        normal, bed = statistics.median(d[0] for d in self.days), self.bed_min()
        earlier = [bed - _clock(d[1]) for d in self.days if d[0] <= normal - DEFICIT and d[1].hour >= 17]
        if len(earlier) < LEARN_DAYS:
            return 0
        shift = statistics.median(earlier)
        return round(min(MAX_BED_SHIFT, shift)) if shift >= 15 else 0


def plan_day(sleeps, birth_date, now, running=None, replan=True):
    """Plan for resten af dagen: kommende lure og sengetid, ud fra hans egne tal.

    sleeps: afsluttede søvn (dicts med id, start, end, nap). running: starttidspunkt for en lur, der er
    i gang (nattesøvn i gang giver ingen plan). Genberegnes hver gang:
    - efter en kort lur (under 30 min) er næste vindue 75 % af det normale, og den kortere lur tæller ikke
      som en af dagens lure
    - aftenlur: plejer han at tage en, og er der ikke plads til en hel lur, planlægges en aftenlur, og sengetiden
      er hans typiske tid vågen efter den (dog tidligst hans normale sengetid)
    - har dagen givet mindre søvn end normalt, rykkes sengetiden kun frem, hvis hans egne data viser, at han
      plejer at sove tidligere på sådanne dage (`learned_shift`)
    - korte «nætter», der sluttede samme aften, læses som aftenlure (`_normalize`)
    - replan=True: er han stadig vågen OVERDUE_MIN efter planlagt lur, er næste lur «nu», og resten af dagen
      flyttes. (Beskederne bruger replan=False, så «virker meget frisk» kommer på det oprindelige tidspunkt.)
    """
    sleeps = sorted((_normalize(s) for s in sleeps), key=lambda s: s["start"])
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
    elif last["nap"] and _clock(last["start"]) >= CATNAP_FROM and m.catnap_habit() and m.evening_gap():
        win = m.evening_gap()  # efter aftenluren: hans typiske tid vågen før natten
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

    items, dropped, catnap_end = [], False, None
    for _ in range(6):
        if t >= bed_on(t) - timedelta(minutes=60):
            break
        length = m.nap_length(k + 1)
        end = t + timedelta(minutes=length)
        if end + timedelta(minutes=m.window(pos + 1)[0]) > bed_on(t) + timedelta(minutes=30):
            if m.catnap_habit():
                # Ingen plads til en hel lur, men han plejer at tage en aftenlur: planlæg den
                length = m.catnap_length()
                catnap_end = t + timedelta(minutes=length)
                items.append({"kind": "lur", "start": t, "end": catnap_end, "catnap": True})
                slept, wake = slept + length, catnap_end
            else:
                dropped = True  # ingen plads og ingen aftenlur: tidligere sengetid i stedet
            break
        items.append({"kind": "lur", "start": t, "end": end})
        k, pos, slept, wake = k + 1, pos + 1, slept + length, end
        win = m.window(pos)[0]
        t = end + timedelta(minutes=win)

    # Sengetid: hans typiske tidspunkt. Rykkes kun frem efter for lidt dagsøvn, hvis hans egne data viser,
    # at han plejer at sove tidligere på sådanne dage. Efter en planlagt aftenlur: hans typiske tid vågen
    # efter den. Er en lur droppet (ingen aftenlur), er det sengetid, når vinduet er gået, dog højst
    # MAX_BED_SHIFT før normalt.
    learned = m.learned_shift()
    shift = learned if learned and slept <= m.normal_day_sleep() - DEFICIT else 0
    floor = t if not shift else wake + timedelta(minutes=win * SHORT_FACTOR)
    if catnap_end:
        shift, floor = 0, catnap_end + timedelta(minutes=m.evening_gap() or m.window(pos + 1)[0])
    elif dropped:
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
        "catnap": m.catnap_habit(),  # han plejer at tage en aftenlur
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


# Notifikationer (web push), sat af app.py: modulet push med active(), send(), load(), wants() og timing()
push = None
# Barnets visningsnavn (sat af app.py fra prefs.json), ellers navnet fra databasen
display_name = None

# Beskedtyper, som hver enhed kan slå til og fra (push.json).
KINDS = ("sleep_soon", "overdue", "pump")


def can_notify(kind=None):
    """Er der nogen enhed, der vil have denne beskedtype (eller nogen besked overhovedet)?"""
    return bool(push and push.active(kind))


def notify(title, msg, kind=None):
    """Send til alle enheder, der vil have beskedtypen."""
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

    # Notifikationer: «slap af» før og «virker frisk» efter, hver kun én gang pr. forudsigelse og enhed,
    # og ikke hvis søvnen allerede er startet. Hver enhed har sine egne minutter (push.json, standard
    # LEAD_MIN/OVERDUE_MIN), og det, der er sendt, huskes pr. enhed (state["push_sent"]).
    until = (pred["time"] - now).total_seconds() / 60

    def due(lead, overdue):
        if 0 <= until <= lead:
            return "sleep_soon"
        if -120 <= until <= -overdue:  # ikke flere timer efter, fx hvis appen har været nede
            return "overdue"
        return None

    devices = []
    if push:
        devices = [(s, k) for s in push.load() for k in [due(*push.timing(s))] if k and push.wants(s, k)]
    if not devices:
        return
    try:
        if db.timer(child["id"]):
            return
    except Exception:
        pass
    state = load_state()
    name = (display_name and display_name()) or child.get("first_name")
    text = {"sleep_soon": soon_text(pred), "overdue": overdue_text(pred, name)}
    old = {"sleep_soon": "notified", "overdue": "overdue"}  # nøglerne fra før minutter pr. enhed
    changed = False
    sent = state.setdefault("push_sent", {})
    for s, k in devices:
        dev = sent.setdefault(device_key(s["endpoint"]), {})
        if dev.get(k, state.get(old[k])) == pred["last_id"]:
            continue
        try:
            push.send("Søvn", text[k], kind=k, endpoints=[s["endpoint"]])
        except Exception as e:
            print("notify push:", e, flush=True)
        dev[k] = pred["last_id"]
        changed = True
    if changed:
        save_state(state)


def device_key(endpoint):
    """Kort, stabil nøgle for en enhed i state.json (selve adressen er lang)."""
    import hashlib
    return hashlib.sha1(endpoint.encode()).hexdigest()[:12]

if __name__ == "__main__":
    main()
