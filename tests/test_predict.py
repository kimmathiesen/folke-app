"""predict() på syntetiske data: 10 dage med nat + 3 lure og faste vågenvinduer."""
from datetime import date, datetime, timedelta

import pytest

import napper
from napper import TZ, default_window, predict

BIRTH = date(2026, 2, 1)
NIGHT = (19, 30)
# (start, slut) pr. lur. Vågenvinduer: 120 min efter natten, 150 efter lur 1, 180 efter lur 2,
# 150 efter lur 3 (frem til sengetid 19:30)
NAPS = [((8, 30), (9, 30)), ((12, 0), (13, 30)), ((16, 30), (17, 0))]


def at(day, hm):
    return datetime(day.year, day.month, day.day, *hm, tzinfo=TZ)


def history(days=10, first=date(2026, 6, 1), naps_last_day=3):
    out, n = [], 0
    for i in range(days):
        d = first + timedelta(days=i)
        n += 1
        out.append({"id": n, "start": at(d - timedelta(days=1), NIGHT), "end": at(d, (6, 30)), "nap": False})
        for s, e in NAPS[: naps_last_day if i == days - 1 else 3]:
            n += 1
            out.append({"id": n, "start": at(d, s), "end": at(d, e), "nap": True})
    return out


def test_ingen_data_giver_none():
    assert predict([], BIRTH, datetime.now(TZ)) is None


def test_eget_moenster_efter_anden_lur():
    sleeps = history(naps_last_day=2)
    last_day = date(2026, 6, 10)
    p = predict(sleeps, BIRTH, at(last_day, (14, 0)))
    assert p["kind"] == "lur"
    assert p["window_min"] == 180
    assert p["time"] == at(last_day, (16, 30))
    assert p["source"] == "eget mønster (position 2)"
    assert p["last_id"] == sleeps[-1]["id"]


def test_morgen_bruger_vindue_efter_natten():
    sleeps = history(naps_last_day=0)
    p = predict(sleeps, BIRTH, at(date(2026, 6, 10), (7, 0)))
    assert p["kind"] == "lur"
    assert p["window_min"] == 120
    assert p["time"] == at(date(2026, 6, 10), (8, 30))


def test_sengetid_efter_sidste_lur():
    sleeps = history(naps_last_day=3)
    last_day = date(2026, 6, 10)
    p = predict(sleeps, BIRTH, at(last_day, (17, 30)))
    assert p["kind"] == "sengetid"
    assert p["time"] == at(last_day, NIGHT)  # median af aftensøvne


def test_raekkefoelge_er_ligegyldig():
    sleeps = history(naps_last_day=2)
    now = at(date(2026, 6, 10), (14, 0))
    assert predict(list(reversed(sleeps)), BIRTH, now) == predict(sleeps, BIRTH, now)


def test_aldersbaseret_standard_uden_nok_data():
    d = date(2026, 6, 10)
    sleeps = [{"id": 1, "start": at(d - timedelta(days=1), NIGHT), "end": at(d, (6, 0)), "nap": False}]
    now = at(d, (6, 30))
    p = predict(sleeps, BIRTH, now)
    age = (now.date() - BIRTH).days  # 129 dage = 4,2 mdr.
    assert p["source"] == "aldersbaseret standard"
    assert p["window_min"] == default_window(age) == 120
    assert p["time"] == at(d, (8, 0))


def test_gennemsnit_af_alle_vinduer_som_fallback():
    # Seks lure i træk: hver position har kun én prøve, men der er 5 vinduer i alt
    d = date(2026, 6, 10)
    sleeps = []
    t = at(d, (6, 0))
    for i in range(6):
        sleeps.append({"id": i + 1, "start": t, "end": t + timedelta(minutes=30), "nap": True})
        t += timedelta(minutes=30 + 60 + i * 2)
    p = predict(sleeps, BIRTH, sleeps[-1]["end"])
    assert p["source"] == "gennemsnit af alle vinduer"
    assert p["window_min"] == 64  # median af 60, 62, 64, 66, 68


def test_urimelige_huller_ignoreres():
    # Huller under 20 min eller over 8 timer tæller ikke med: kun 3 gyldige vinduer af 5,
    # så der er ikke nok til gennemsnittet, og aldersstandarden bruges
    sleeps, t = [], at(date(2026, 6, 10), (0, 0))
    for i, gap in enumerate([60, 10, 60, 600, 60, 0]):
        sleeps.append({"id": i + 1, "start": t, "end": t + timedelta(minutes=30), "nap": True})
        t += timedelta(minutes=30 + gap)
    p = predict(sleeps, BIRTH, sleeps[-1]["end"])
    assert p["source"] == "aldersbaseret standard"


@pytest.mark.parametrize("days,mins", [(0, 60), (70, 75), (100, 90), (150, 120), (250, 150),
                                       (330, 180), (500, 210), (700, 270)])
def test_default_window(days, mins):
    assert napper.default_window(days) == mins
