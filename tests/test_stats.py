"""Søvn i tal (stats.py)."""
from datetime import date, datetime, timedelta

from folke import TZ
import stats

TODAY = date(2026, 10, 17)
NOW = datetime(2026, 10, 17, 12, 0, tzinfo=TZ)


def at(d, h, m=0):
    return datetime(d.year, d.month, d.day, h, m, tzinfo=TZ)


def history(days=14, missing=(), wake_nights=()):
    """Hver dag: lure 9:30-10:30 og 14:00-15:30, nat 20:30-07:00. Ugen før (dag 8-14 siden): nat 20:00-06:30.
    `missing`: dage siden i dag uden nat. `wake_nights`: nætter med én opvågning på 30 min."""
    sleeps, wakes = [], []
    for i in range(days, 0, -1):
        d = TODAY - timedelta(days=i)
        sleeps += [{"start": at(d, 9, 30), "end": at(d, 10, 30), "nap": True},
                   {"start": at(d, 14, 0), "end": at(d, 15, 30), "nap": True}]
        if i in missing:
            continue
        b, w = ((20, 0), (6, 30)) if i > 7 else ((20, 30), (7, 0))
        sleeps.append({"start": at(d, *b), "end": at(d + timedelta(days=1), *w), "nap": False})
        if i in wake_nights:
            wakes.append({"start": at(d, 23, 0), "end": at(d, 23, 30)})
    return sleeps, wakes


def test_en_dag():
    s, w = history(wake_nights=(1,))
    d = stats.day(s, w, TODAY - timedelta(days=1))
    assert d == {"date": "2026-10-16", "naps": 2, "day_min": 150, "night_min": 600, "total_min": 750,
                 "bed": 20 * 60 + 30, "wake": 7 * 60, "wakes": 1, "nap_len": 75}


def test_uge_mod_ugen_foer():
    s, w = history()
    r = stats.stats(s, w, NOW, "Folke")
    assert len(r["days"]) == 14 and r["days"][-1]["date"] == "2026-10-16"
    assert r["week"] == {"days": 7, "total_min": 780, "night_min": 630, "day_min": 150, "naps": 2.0, "nap_len": 75,
                         "bed": 20 * 60 + 30, "wake": 7 * 60, "wakes": None}
    assert r["prev"]["bed"] == 20 * 60 and r["prev"]["night_min"] == 630
    assert r["prev"]["wake"] == 6 * 60 + 30  # første dag i vinduet har ingen nat før sig og tæller ikke med her
    assert r["text"] == "Folke sover i gennemsnit 13 t i døgnet, heraf 10 t 30 min om natten."


def test_manglende_nat_taeller_ikke_med():
    s, w = history(missing=(1,))
    r = stats.stats(s, w, NOW)
    assert r["week"]["days"] == 6 and r["week"]["total_min"] == 780
    assert r["days"][-1]["night_min"] is None and r["days"][-1]["day_min"] == 150
    assert r["text"].startswith("Jeres barn sover")


def test_opvaagninger_kun_naar_de_registreres():
    s, w = history(wake_nights=(1, 2))
    r = stats.stats(s, w, NOW)
    assert r["week"]["wakes"] == round(2 / 7 * 10) / 10 and r["week"]["night_min"] == round((630 * 5 + 600 * 2) / 7)


def test_uden_data():
    r = stats.stats([], [], NOW)
    assert r["week"]["days"] == 0 and r["text"] is None and r["days"][0] == {"date": "2026-10-03"}


def test_sengetid_efter_midnat():
    assert stats._median_clock([23 * 60 + 50, 10, 30], evening=True) == 10


def test_api(client, world):
    from datetime import datetime as dt
    now = dt.now(TZ)
    for i in range(1, 4):
        d = now.date() - timedelta(days=i)
        world.add_sleep(at(d, 9, 0), at(d, 10, 0))
        world.add_sleep(at(d, 20, 0), at(d + timedelta(days=1), 6, 0), nap=False)
    r = client.get("/api/stats").get_json()
    assert r["week"]["days"] == 3 and r["week"]["total_min"] == 660 and len(r["days"]) == 14
