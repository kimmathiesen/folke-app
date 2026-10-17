"""Glemt nat (folke.missing_night) og «Tilføj glemt søvn» (POST /api/sleep)."""
from datetime import date, datetime, timedelta

import pytest

import folke
from folke import TZ

DAY = date(2026, 10, 17)


def at(d, h, m=0):
    return datetime(d.year, d.month, d.day, h, m, tzinfo=TZ)


def week(last=DAY - timedelta(days=1), nights=True):
    """En uge med nat 20:40-07:30 og lure. Den sidste dag (`last`) har lure til 17:45, men ingen nat bagefter."""
    out = []
    for i in range(7, 0, -1):
        d = last - timedelta(days=i)
        out += [{"start": at(d, 9, 30), "end": at(d, 10, 30), "nap": True},
                {"start": at(d, 14, 0), "end": at(d, 15, 0), "nap": True}]
        if nights:
            out.append({"start": at(d, 20, 40), "end": at(d + timedelta(days=1), 7, 30), "nap": False})
    out += [{"start": at(last, 9, 31), "end": at(last, 10, 27), "nap": True},
            {"start": at(last, 16, 34), "end": at(last, 17, 45), "nap": True}]
    return out


def test_folkes_glemte_nat():
    # 17/10: lur 08:37-09:27, en lur kører fra 11:24, klokken er 12:08
    sleeps = week() + [{"start": at(DAY, 8, 37), "end": at(DAY, 9, 27), "nap": True}]
    m = folke.missing_night(sleeps, at(DAY, 12, 8), running=at(DAY, 11, 24))
    assert m == {"start": at(DAY - timedelta(days=1), 20, 40), "end": at(DAY, 7, 30)}


def test_slutter_senest_ved_foerste_soevn_i_dag_eller_nu():
    sleeps = week() + [{"start": at(DAY, 7, 0), "end": at(DAY, 7, 40), "nap": True}]
    assert folke.missing_night(sleeps, at(DAY, 8, 0))["end"] == at(DAY, 7, 0)
    assert folke.missing_night(week(), at(DAY, 6, 10))["end"] == at(DAY, 6, 10)


def test_starter_tidligst_efter_sidste_soevn_i_gaar():
    sleeps = week() + [{"start": at(DAY - timedelta(days=1), 19, 30), "end": at(DAY - timedelta(days=1), 21, 0), "nap": True}]
    assert folke.missing_night(sleeps, at(DAY, 9, 0))["start"] == at(DAY - timedelta(days=1), 21, 0)


def test_uden_historik_bruges_standardtider():
    assert folke.missing_night(week(nights=False), at(DAY, 9, 0)) == \
        {"start": at(DAY - timedelta(days=1), 19, 30), "end": at(DAY, 6, 30)}


@pytest.mark.parametrize("case", ["natten findes", "for tidligt", "i går ikke registreret", "natten kører"])
def test_ingen_besked(case):
    sleeps, now, running = week(), at(DAY, 9, 0), None
    if case == "natten findes":
        sleeps.append({"start": at(DAY - timedelta(days=1), 20, 30), "end": at(DAY, 6, 50), "nap": False})
    elif case == "for tidligt":
        now = at(DAY, 4, 30)
    elif case == "i går ikke registreret":
        sleeps = week(last=DAY - timedelta(days=2))
    else:
        running = at(DAY - timedelta(days=1), 20, 45)
    assert folke.missing_night(sleeps, now, running) is None


def iso(t):
    return t.strftime("%Y-%m-%dT%H:%M")


def test_tilfoej_glemt_nat(client, world):
    now = datetime.now(TZ)
    y = now.date() - timedelta(days=1)
    r = client.post("/api/sleep", json={"start": iso(at(y, 3, 0)), "end": iso(at(y, 6, 0)), "nap": False})
    assert r.status_code == 200
    [s] = world.sleeps()
    assert folke.parse(s["start"]) == at(y, 3, 0) and not s["nap"]


@pytest.mark.parametrize("body,fejl", [
    ({"start": "x", "end": "y"}, "Ugyldigt tidspunkt"),
    ({"start": "2026-10-10T06:00", "end": "2026-10-10T05:00"}, "Vågnede skal være efter"),
    ({"start": "2026-10-09T06:00", "end": "2026-10-10T05:00"}, "højst vare 16 timer"),
])
def test_tilfoej_afviser(client, world, body, fejl):
    r = client.post("/api/sleep", json=body)
    assert r.status_code == 400 and fejl in r.get_json()["error"]


def test_tilfoej_afviser_fremtid_og_overlap(client, world):
    now = datetime.now(TZ).replace(second=0, microsecond=0)
    r = client.post("/api/sleep", json={"start": iso(now), "end": iso(now + timedelta(hours=1))})
    assert "fremtiden" in r.get_json()["error"]
    world.add_sleep(now - timedelta(hours=5), now - timedelta(hours=4))
    r = client.post("/api/sleep", json={"start": iso(now - timedelta(hours=6)), "end": iso(now - timedelta(hours=4, minutes=30))})
    assert r.status_code == 400 and "Overlapper" in r.get_json()["error"]
    world.add_timer(now - timedelta(hours=1))
    r = client.post("/api/sleep", json={"start": iso(now - timedelta(hours=2)), "end": iso(now - timedelta(minutes=30))})
    assert "i gang" in r.get_json()["error"]


def test_status_har_glemt_nat(client, world):
    now = datetime.now(TZ)
    if now.hour < 6:
        pytest.skip("reglen siger intet før kl. 5")
    y = now.date() - timedelta(days=1)
    world.add_sleep(at(y, 9, 0), at(y, 10, 0))
    m = client.get("/api/status").get_json()["missing_night"]
    assert m and m["start"].startswith(y.isoformat())
