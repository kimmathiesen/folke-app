"""Søvn i tal: de seneste 14 hele dage og gennemsnit for de seneste 7 dage mod ugen før.

En dag er lurene, der starter den dag, og natten, der starter samme aften (minus tid vågen om natten). «Vågnede» er,
da natten før sluttede. Dage, hvor natten mangler (fx glemt at trykke), vises, men tæller ikke med i gennemsnittene.
Samme regler i Swift: ios/FolkeCore/Sources/FolkeCore/SleepStats.swift (fælles testdata i tests/fixtures/stats).
"""
import statistics
from datetime import timedelta

from folke import TZ

DAYS = 14


def _mins(a, b):
    return (b - a).total_seconds() / 60


def _clock(t):
    t = t.astimezone(TZ)
    return t.hour * 60 + t.minute


def day(sleeps, wakes, d):
    """Tallene for dagen d (dato). None, hvis intet er registreret den dag."""
    loc = lambda t: t.astimezone(TZ)  # noqa: E731
    naps = [s for s in sleeps if s["nap"] and loc(s["start"]).date() == d]
    nights = [s for s in sleeps if not s["nap"] and loc(s["start"]).date() == d]
    before = [s for s in sleeps if not s["nap"] and loc(s["end"]).date() == d and loc(s["start"]).date() < d]
    if not naps and not nights:
        return None
    n = max(nights, key=lambda s: _mins(s["start"], s["end"]), default=None)
    ws = [w for w in wakes if n and n["start"] <= w["start"] <= n["end"]]
    awake = sum(_mins(w["start"], min(w["end"] or n["end"], n["end"])) for w in ws)
    nap_min = sum(_mins(s["start"], s["end"]) for s in naps)
    night_min = _mins(n["start"], n["end"]) - awake if n else None
    return {"date": d.isoformat(), "naps": len(naps), "day_min": round(nap_min),
            "night_min": None if night_min is None else round(night_min),
            "total_min": None if night_min is None else round(nap_min + night_min),
            "bed": _clock(n["start"]) if n else None,
            "wake": _clock(max(before, key=lambda s: s["end"])["end"]) if before else None,
            "wakes": len(ws) if n else None,
            "nap_len": round(nap_min / len(naps)) if naps else None}


def _avg(xs):
    """Gennemsnit afrundet til hele (round half to even, som Swift .toNearestOrEven)."""
    xs = [x for x in xs if x is not None]
    return round(sum(xs) / len(xs)) if xs else None


def _avg1(xs):
    """Gennemsnit med én decimal."""
    xs = [x for x in xs if x is not None]
    return round(sum(xs) / len(xs) * 10) / 10 if xs else None


def _median_clock(xs, evening=False):
    """Median af klokkeslæt i minutter. Om aftenen tæller tider efter midnat som sene (fx 00:30 = 24:30)."""
    xs = [x + (1440 if evening and x < 12 * 60 else 0) for x in xs if x is not None]
    return round(statistics.median(xs)) % 1440 if xs else None


def summary(days, tracks_wakes):
    """Gennemsnit over hele dage (med en nat). Opvågninger kun, hvis de bliver registreret."""
    full = [d for d in days if d and d["night_min"] is not None]
    return {"days": len(full),
            "total_min": _avg([d["total_min"] for d in full]),
            "night_min": _avg([d["night_min"] for d in full]),
            "day_min": _avg([d["day_min"] for d in full]),
            "naps": _avg1([d["naps"] for d in full]),
            "nap_len": _avg([d["nap_len"] for d in full]),
            "bed": _median_clock([d["bed"] for d in full], evening=True),
            "wake": _median_clock([d["wake"] for d in full]),
            "wakes": _avg1([d["wakes"] for d in full]) if tracks_wakes else None}


def _dur(m):
    h, m = divmod(int(m), 60)
    return f"{h} t {m} min" if h and m else f"{h} t" if h else f"{m} min"


def stats(sleeps, wakes, now, name=""):
    today = now.astimezone(TZ).date()
    dates = [today - timedelta(days=i) for i in range(DAYS, 0, -1)]
    days = [day(sleeps, wakes, d) for d in dates]
    tracks = len(wakes) > 0
    week, prev = summary(days[7:], tracks), summary(days[:7], tracks)
    text = None
    if week["days"]:
        text = (f"{name or 'Jeres barn'} sover i gennemsnit {_dur(week['total_min'])} i døgnet, "
                f"heraf {_dur(week['night_min'])} om natten.")
    return {"days": [d or {"date": x.isoformat()} for d, x in zip(days, dates)], "week": week, "prev": prev,
            "text": text}
