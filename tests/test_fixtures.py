"""Fælles testdata (tests/fixtures): de samme filer køres af Swift (ios/FolkeCore, FixtureTests)."""
import glob
import json
import os
from datetime import date, datetime

import pytest

import evaluate
from folke import TZ, plan_day

HERE = os.path.join(os.path.dirname(__file__), "fixtures")
FILES = sorted(glob.glob(os.path.join(HERE, "dayplan", "*.json")))


def sleeps(data):
    p = lambda t: datetime.fromisoformat(t).astimezone(TZ)  # noqa: E731
    return [{"id": s["id"], "start": p(s["start"]), "end": p(s["end"]), "nap": s["nap"]} for s in data["sleeps"]]


def hm(t):
    return t and f"{t.astimezone(TZ):%H:%M}"


def test_der_er_fixtures():
    assert len(FILES) >= 8


@pytest.mark.parametrize("path", FILES, ids=[os.path.basename(f)[:-5] for f in FILES])
def test_dagsplan(path):
    d = json.load(open(path))
    now = datetime.fromisoformat(d["now"])
    running = d["running"] and datetime.fromisoformat(d["running"])
    p = plan_day(sleeps(d), date.fromisoformat(d["birth_date"]), now, running=running)
    got = {
        "items": [{"kind": x["kind"], "start": hm(x["start"]), "end": hm(x.get("end")), "catnap": bool(x.get("catnap"))}
                  for x in p["items"]],
        "wake": hm(p["wake"]), "missed_at": hm(p["missed_at"]), "short": p["short"], "bed_shift": p["bed_shift"],
        "first_window": p["first_window"], "after_catnap": p["after_catnap"],
    }
    assert got == d["expect"], d["description"]


def test_maaling():
    d = json.load(open(os.path.join(HERE, "backtest.json")))
    res = evaluate.backtest(sleeps(d), date.fromisoformat(d["birth_date"]))
    s = evaluate.summary(res)
    assert {k: s[k] for k in ("n", "median_abs", "within_15", "within_30")} == \
        {k: d["expect"][k] for k in ("n", "median_abs", "within_15", "within_30")}
    assert list(evaluate.interval([r["error"] for r in res])) == d["expect"]["interval"]
