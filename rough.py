"""Urolig søvn: en blid besked, når søvnen er tydeligt dårligere end normalt.

De seneste 4 hele dage holdes op mod de 14 dage før. Er mindst to ting tydeligt dårligere (flere opvågninger,
kortere nætter, kortere lure, flere korte lure, mindre dagsøvn), kommer en besked. Ligger barnet samtidig i en
kendt periode (fx 4-måneders søvnregressionen), forklarer beskeden den. Tigerspring er bevidst ikke med.
Samme regler i Swift: ios/FolkeCore/Sources/FolkeCore/RoughPatch.swift (fælles testdata i tests/fixtures/rough).
"""
from datetime import timedelta

from folke import SHORT_NAP, TZ

RECENT_DAYS = 4    # de seneste hele dage
BASE_DAYS = 14     # sammenlignet med dagene før
MIN_RECENT = 3     # dage med registreringer, før der siges noget
MIN_BASE = 7
MIN_FLAGS = 2      # så mange ting skal være tydeligt dårligere

# (id, fra uge, til uge (ikke medregnet), forklaring). Ugerne regnes fra fødslen.
PERIODS = [
    ("4m", 14, 23, "Omkring 4 måneder ændrer søvnen sig hos mange børn: den bliver lettere og mere som voksnes. "
                   "Det kaldes ofte 4-måneders søvnregressionen og kan give flere opvågninger og kortere lure i en periode."),
    ("8m", 34, 47, "Omkring 8–10 måneder øver mange børn sig i at kravle og rejse sig, og de lægger mere mærke til, "
                   "når du går. Det kan give uroligere søvn i en periode."),
    ("12m", 50, 57, "Omkring 1 år går mange børn fra to lure mod én, og nye ting som at gå kan forstyrre søvnen "
                    "i en periode."),
    ("18m", 76, 85, "Omkring 1½ år vil mange børn gerne bestemme mere selv, og hjørnetænderne kommer ofte. "
                    "Det kan give mere uro ved puttetid og om natten."),
    ("24m", 100, 109, "Omkring 2 år tester mange børn grænser ved puttetid, og fantasien vokser, så nogle får "
                      "sværere ved at falde til ro."),
]

# I den rækkefølge, de nævnes
REASONS = [("wakes", "flere opvågninger om natten"), ("night", "kortere nætter"), ("naps", "kortere lure"),
           ("short", "flere korte lure"), ("day", "mindre søvn om dagen")]

TITLE = "Søvnen er lidt urolig lige nu"
OTHER = ("Det sker for alle børn en gang imellem, fx ved tænder, forkølelse eller nye ting, de øver sig på. "
         "Det går som regel over igen.")


def period(birth, today):
    weeks = (today - birth).days // 7
    return next((p for p in PERIODS if p[1] <= weeks < p[2]), None)


def _mins(a, b):
    return (b - a).total_seconds() / 60


def _days(sleeps, wakes, first, n):
    """Tal pr. dag for dagene first .. first+n-1 (kun dage med registreringer). Natten hører til dagen, den starter."""
    out = []
    for i in range(n):
        d = first + timedelta(days=i)
        naps = [s for s in sleeps if s["nap"] and s["start"].astimezone(TZ).date() == d]
        nights = [s for s in sleeps if not s["nap"] and s["start"].astimezone(TZ).date() == d]
        if not naps and not nights:
            continue
        ws = [w for n_ in nights for w in wakes if n_["start"] <= w["start"] <= n_["end"]]
        awake = sum(_mins(w["start"], min(w["end"] or n_["end"], n_["end"])) for n_ in nights for w in wakes
                    if n_["start"] <= w["start"] <= n_["end"])
        out.append({"naps": [_mins(s["start"], s["end"]) for s in naps],
                    "night": sum(_mins(s["start"], s["end"]) for s in nights) - awake if nights else None,
                    "wakes": len(ws)})
    return out


def _mean(xs):
    return sum(xs) / len(xs) if xs else None


def _stats(days):
    lens = [x for d in days for x in d["naps"]]
    return {"day": _mean([sum(d["naps"]) for d in days]),
            "nap_len": _mean(lens),
            "short": _mean([sum(1 for x in d["naps"] if x < SHORT_NAP) for d in days]),
            "night": _mean([d["night"] for d in days if d["night"] is not None]),
            "wakes": _mean([d["wakes"] for d in days if d["night"] is not None])}


def check(sleeps, wakes, birth, now, name=""):
    """En besked om urolig søvn, eller None. sleeps: [{start, end, nap}], wakes: [{start, end}] (datetimes)."""
    today = now.astimezone(TZ).date()
    recent = _days(sleeps, wakes, today - timedelta(days=RECENT_DAYS), RECENT_DAYS)
    base_first = today - timedelta(days=RECENT_DAYS + BASE_DAYS)
    base = _days(sleeps, wakes, base_first, BASE_DAYS)
    if len(recent) < MIN_RECENT or len(base) < MIN_BASE:
        return None
    r, b = _stats(recent), _stats(base)
    flags = set()
    # Opvågninger tæller kun, hvis de også blev registreret før (ellers ligner det en forværring, at man er begyndt)
    if b["wakes"] is not None and r["wakes"] is not None and sum(d["wakes"] for d in base) > 0 \
            and r["wakes"] >= b["wakes"] + 1 and r["wakes"] >= 1.5 * b["wakes"]:
        flags.add("wakes")
    if b["night"] and r["night"] is not None and r["night"] <= 0.85 * b["night"]:
        flags.add("night")
    if b["nap_len"] and r["nap_len"] is not None and r["nap_len"] <= 0.75 * b["nap_len"]:
        flags.add("naps")
    if b["short"] is not None and r["short"] is not None and r["short"] >= b["short"] + 1:
        flags.add("short")
    if b["day"] and r["day"] is not None and r["day"] <= 0.8 * b["day"]:
        flags.add("day")
    if len(flags) < MIN_FLAGS:
        return None
    reasons = [k for k, _ in REASONS if k in flags]
    words = [t for k, t in REASONS if k in flags]
    why = words[0] if len(words) == 1 else ", ".join(words[:-1]) + " og " + words[-1]
    p = period(birth, today)
    y, w, _ = today.isocalendar()
    who = name or "Jeres barn"
    text = f"{who} har sovet lidt dårligere de seneste dage ({why}). {p[3] if p else OTHER} Husk, at du gør det godt."
    return {"key": f"p-{p[0]}" if p else f"u-{y}-{w:02d}", "period": p and p[0], "reasons": reasons,
            "title": TITLE, "text": text}
