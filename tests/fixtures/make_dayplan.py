#!/usr/bin/env python3
"""Fælles testdata for dagsplanen (og urolig søvn): scenarier -> JSON med folke.plan_day og rough.check som facit.

Både tests/test_fixtures.py (Python) og ios/FolkeCore (Swift, FixtureTests) indlæser filerne, så reglerne
ikke kan glide fra hinanden. Kør igen efter en bevidst ændring af reglerne, og commit de nye filer:

    python tests/fixtures/make_dayplan.py
"""
import json
import os
import sys
from datetime import date, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [os.path.dirname(HERE), os.path.dirname(os.path.dirname(HERE))]

import evaluate  # noqa: E402
import messages  # noqa: E402
import rough  # noqa: E402
from folke import plan_day  # noqa: E402
from test_dayplan import catnap_history  # noqa: E402
from test_predict import BIRTH, at, history  # noqa: E402
import test_rough  # noqa: E402

DAY, CAT = date(2026, 6, 10), date(2026, 6, 11)


def naps(d, spans, first_id=900):
    return [{"id": first_id + i, "start": at(d, a), "end": at(d, b), "nap": True} for i, (a, b) in enumerate(spans)]


FULL = [((9, 0), (10, 0)), ((12, 30), (14, 0))]

# (navn, beskrivelse, søvn, nu, kørende lur)
SCENARIOS = [
    ("morgen", "Hele dagen om morgenen", history(naps_last_day=0), at(DAY, (7, 0)), None),
    ("efter-1-lur", "Efter 1. lur, som varede 30 min længere end normalt",
     history(naps_last_day=0) + naps(DAY, [((8, 30), (10, 0))]), at(DAY, (10, 5)), None),
    ("kort-lur", "En kort lur i barnevognen kl. 11", history(naps_last_day=1) + naps(DAY, [((11, 0), (11, 15))]),
     at(DAY, (11, 20)), None),
    ("misset-lur", "2. lur var planlagt 12.00, men han er stadig vågen", history(naps_last_day=1), at(DAY, (12, 20)), None),
    ("lur-i-gang", "2. lur er i gang", history(naps_last_day=1), at(DAY, (12, 30)), at(DAY, (12, 0))),
    ("aftenlur-planlaegges", "Lang eftermiddagslur: der er kun plads til en aftenlur",
     catnap_history() + naps(CAT, FULL + [((16, 30), (18, 30))]), at(CAT, (18, 35)), None),
    ("efter-aftenlur", "Aftenluren er sovet", catnap_history() + naps(CAT, FULL + [((16, 0), (17, 0)), ((19, 0), (19, 45))]),
     at(CAT, (19, 50)), None),
    ("kort-aftenlur", "To korte lure, den sidste efter kl. 17 (Folke 8/10)",
     catnap_history() + naps(CAT, FULL + [((16, 32), (16, 53)), ((18, 6), (18, 26))]), at(CAT, (18, 35)), None),
    ("kort-foerste-lur", "Kort første lur med aftenlur-vane", catnap_history() + naps(CAT, [((9, 0), (9, 20))]),
     at(CAT, (9, 25)), None),
]


def iso(t):
    return t.isoformat()


def hm(t):
    return t and f"{t:%H:%M}"


def write(name, desc, sleeps, now, running):
    p = plan_day(sleeps, BIRTH, now, running=running)
    data = {
        "description": desc,
        "birth_date": BIRTH.isoformat(),
        "now": iso(now),
        "running": running and iso(running),
        "sleeps": [{"id": s["id"], "start": iso(s["start"]), "end": iso(s["end"]), "nap": s["nap"]}
                   for s in sorted(sleeps, key=lambda s: s["start"])],
        "expect": {
            "items": [{"kind": x["kind"], "start": hm(x["start"]), "end": hm(x.get("end")),
                       "catnap": bool(x.get("catnap"))} for x in p["items"]],
            "wake": hm(p["wake"]), "missed_at": hm(p["missed_at"]), "short": p["short"],
            "bed_shift": p["bed_shift"], "first_window": p["first_window"], "after_catnap": p["after_catnap"],
        },
    }
    with open(os.path.join(HERE, "dayplan", f"{name}.json"), "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")


def write_backtest():
    """Målingen på den syntetiske aftenlur-historik med en skæv dag til sidst."""
    sleeps = catnap_history() + naps(CAT, FULL + [((16, 32), (16, 53)), ((18, 6), (18, 26))])
    sleeps.append({"id": 999, "start": at(CAT, (19, 50)), "end": at(CAT + timedelta(days=1), (7, 0)), "nap": False})
    res = evaluate.backtest(sleeps, BIRTH)
    s = evaluate.summary(res)
    data = {"description": "evaluate.backtest på aftenlur-historikken + Folkes dag 8/10", "birth_date": BIRTH.isoformat(),
            "sleeps": [{"id": x["id"], "start": iso(x["start"]), "end": iso(x["end"]), "nap": x["nap"]}
                       for x in sorted(sleeps, key=lambda x: x["start"])],
            "expect": {"n": s["n"], "median_abs": s["median_abs"], "within_15": s["within_15"],
                       "within_30": s["within_30"], "interval": list(evaluate.interval([r["error"] for r in res]))}}
    with open(os.path.join(HERE, "backtest.json"), "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")


# Urolig søvn: (navn, beskrivelse, fødselsdato, navn på barnet, argumenter til test_rough.history)
ROUGH = [
    ("4m-urolig", "4 urolige dage midt i 4-måneders perioden", test_rough.BIRTH_4M, "Folke", {}),
    ("urolig-uden-periode", "4 urolige dage uden for de kendte perioder", test_rough.BIRTH_6M, "", {}),
    ("4m-fint", "I perioden, men søvnen er som normalt", test_rough.BIRTH_4M, "Folke", {"bad": 0}),
    ("en-daarlig-dag", "Kun én dårlig dag", test_rough.BIRTH_4M, "Folke", {"bad": 1}),
    ("kun-opvaagninger", "Kun flere opvågninger, lurene er normale", test_rough.BIRTH_4M, "Folke", {"bad_naps": False}),
    ("opvaagninger-kun-nu", "Opvågninger er først registreret nu og tæller ikke", test_rough.BIRTH_4M, "Folke",
     {"wakes_before": False}),
    ("for-lidt-data", "Kun 2 af de seneste 4 dage registreret", test_rough.BIRTH_4M, "Folke", {"gaps": (1, 2)}),
]


def write_rough(name, desc, birth, child, kw):
    sleeps, wakes = test_rough.history(**kw)
    data = {"description": desc, "birth_date": birth.isoformat(), "now": iso(test_rough.NOW), "name": child,
            "sleeps": [{"id": x["id"], "start": iso(x["start"]), "end": iso(x["end"]), "nap": x["nap"]} for x in sleeps],
            "wakes": [{"start": iso(w["start"]), "end": w["end"] and iso(w["end"])} for w in wakes],
            "expect": rough.check(sleeps, wakes, birth, test_rough.NOW, child)}
    os.makedirs(os.path.join(HERE, "rough"), exist_ok=True)
    with open(os.path.join(HERE, "rough", f"{name}.json"), "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")


def write_messages():
    """Notifikationernes tekster og et par valg, så Swift har præcis de samme (Messages.swift)."""
    from datetime import datetime
    from folke import TZ
    whens = [datetime(2026, 10, 17, 13, 40, tzinfo=TZ), datetime(2026, 10, 17, 19, 33, tzinfo=TZ),
             datetime(2026, 12, 31, 23, 59, tzinfo=TZ)]
    picks = [{"kind": k, "when": iso(w), "name": n, "t": "13:40", "h": "3", "expect": messages.pick(k, w, n, "13:40", "3")}
             for k in messages.ALL for w in whens for n in ("Folke", "")]
    with open(os.path.join(HERE, "messages.json"), "w") as f:
        json.dump({"description": "messages.py: lister og valg (minutter siden 1970 modulo 10)", "lists": messages.ALL,
                   "picks": picks}, f, ensure_ascii=False, indent=1)
        f.write("\n")


if __name__ == "__main__":
    for sc in SCENARIOS:
        write(*sc)
    write_backtest()
    for sc in ROUGH:
        write_rough(*sc)
    write_messages()
    print(f"{len(SCENARIOS)} dagsplaner, 1 måling og {len(ROUGH)} om urolig søvn skrevet")
