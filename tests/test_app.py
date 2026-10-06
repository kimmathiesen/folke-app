"""API'erne i app.py, kørt mod både Baby Buddy (falsk) og SQLite via `world`-fixturen."""
from datetime import date, datetime, timedelta

import pytest

import folke

TZ = folke.TZ


def now():
    return datetime.now(TZ)


def hm(t):
    return f"{t:%H:%M}"


# ---------- status ----------
def test_status_uden_data(client):
    d = client.get("/api/status").get_json()
    assert d["sleeping"] is False
    assert d["prediction"] is None
    assert d["today"] == []
    assert d["features"] == {"breast": True, "solids": False, "pump": True}
    assert d["pump"] == {"today_ml": 0, "today_count": 0, "last": None}
    assert d["suggestions"] == []


def test_status_med_soevn_giver_forudsigelse(client, world):
    t = now().replace(microsecond=0)
    world.add_sleep(t - timedelta(days=1, hours=3), t - timedelta(days=1, hours=2))
    sid = world.add_sleep(t - timedelta(minutes=30), t)
    d = client.get("/api/status").get_json()
    assert d["prediction"]["last_id"] == sid
    assert d["prediction"]["source"] == "aldersbaseret standard"
    assert datetime.fromisoformat(d["awake_since"]) == t
    assert sid in [x["id"] for x in d["today"]]
    assert d["backend"] == world.store.name


# ---------- start/stop ----------
def test_start_opretter_timer_og_er_idempotent(client, world):
    assert client.post("/api/start").get_json() == {"ok": True}
    assert client.post("/api/start").status_code == 200
    assert len(world.timers()) == 1
    assert world.timers()[0]["name"] == "Søvn"
    d = client.get("/api/status").get_json()
    assert d["sleeping"] is True and d["prediction"] is None


def test_start_med_tidspunkt(client, world):
    since = now() - timedelta(minutes=20)
    assert client.post("/api/start", json={"since": hm(since)}).status_code == 200
    assert hm(folke.parse(world.timers()[0]["start"])) == hm(since)


def test_start_ugyldigt_tidspunkt(client, world):
    assert client.post("/api/start", json={"since": "xx"}).status_code == 400
    assert world.timers() == []


def test_start_foer_forrige_soevn_afvises(client, world):
    t = now()
    world.add_sleep(t - timedelta(hours=2), t - timedelta(minutes=30))
    r = client.post("/api/start", json={"since": hm(t - timedelta(hours=1))})
    assert r.status_code == 400
    assert "Forrige søvn" in r.get_json()["error"]


def test_stop_uden_timer(client):
    assert client.post("/api/stop").status_code == 409


def test_stop_gemmer_soevn_og_sletter_timer(client, world):
    st = (now() - timedelta(hours=1)).replace(microsecond=0)
    world.add_timer(st)
    assert client.post("/api/stop", json={"nap": True}).status_code == 200
    assert world.timers() == []
    [s] = world.sleeps()
    assert folke.parse(s["start"]) == st and s["nap"] is True


def test_stop_uden_valg_gaetter_ud_fra_start_og_laengde(client, world):
    st = (now() - timedelta(minutes=47)).replace(microsecond=0)
    world.add_timer(st)
    assert client.post("/api/stop", json={}).status_code == 200
    [s] = world.sleeps()
    assert s["nap"] is folke.nap_at_stop(st, folke.parse(s["end"]))


def test_stop_med_vaagnetidspunkt(client, world):
    world.add_timer(now() - timedelta(hours=2))
    wake = now() - timedelta(minutes=30)
    assert client.post("/api/stop", json={"wake": hm(wake), "nap": False}).status_code == 200
    assert hm(folke.parse(world.sleeps()[0]["end"])) == hm(wake)


def test_stop_vaagnet_foer_start_afvises(client, world):
    world.add_timer(now() - timedelta(hours=1))
    r = client.post("/api/stop", json={"wake": hm(now() - timedelta(hours=2))})
    assert r.status_code == 400
    assert len(world.timers()) == 1 and world.sleeps() == []


# ---------- ret/slet søvn ----------
def test_ret_og_slet_soevn(client, world):
    sid = world.add_sleep(now() - timedelta(hours=5), now() - timedelta(hours=4))
    y = (now() - timedelta(days=1)).date()
    r = client.post(f"/api/sleep/{sid}", json={"start": f"{y}T13:00", "end": f"{y}T14:15", "nap": False})
    assert r.status_code == 200
    [s] = world.sleeps()
    assert folke.parse(s["end"]) == datetime.fromisoformat(f"{y}T14:15").replace(tzinfo=TZ)
    assert s["nap"] is False
    assert client.delete(f"/api/sleep/{sid}").status_code == 200
    assert world.sleeps() == []


def test_ret_soevn_slut_foer_start(client, world):
    sid = world.add_sleep(now() - timedelta(hours=5), now() - timedelta(hours=4))
    y = (now() - timedelta(days=1)).date()
    r = client.post(f"/api/sleep/{sid}", json={"start": f"{y}T14:00", "end": f"{y}T13:00"})
    assert r.status_code == 400


# ---------- mad og pumpning ----------
@pytest.mark.parametrize("amount", [0, -5, 2000, "abc", None])
def test_pump_ugyldig(client, world, amount):
    assert client.post("/api/pump", json={"amount": amount}).status_code == 400
    assert world.pumpings() == []


def test_pump(client, world):
    assert client.post("/api/pump", json={"amount": 120}).get_json() == {"ok": True, "amount": 120.0}
    assert world.pumpings()[0]["amount"] == 120.0


@pytest.mark.parametrize("body,expect", [
    ({"kind": "left"}, {"type": "breast milk", "method": "left breast"}),
    ({"kind": "both"}, {"type": "breast milk", "method": "both breasts"}),
    ({"kind": "bottle", "amount": 90}, {"type": "breast milk", "method": "bottle", "amount": 90.0}),
    ({"kind": "bottle", "amount": 90, "milk": "formula"}, {"type": "formula", "method": "bottle"}),
    ({"kind": "solid", "note": "gulerod"}, {"type": "solid food", "notes": "gulerod"}),
])
def test_feed(client, world, body, expect):
    assert client.post("/api/feed", json=body).status_code == 200
    f = world.feedings()[0]
    assert expect.items() <= f.items()


@pytest.mark.parametrize("body", [{"kind": "x"}, {"kind": "bottle"}, {"kind": "bottle", "amount": 600},
                                  {"kind": "left", "at": "aa:bb"}])
def test_feed_ugyldig(client, world, body):
    assert client.post("/api/feed", json=body).status_code == 400
    assert world.feedings() == []


def test_feed_med_tidspunkt(client, world):
    t = now() - timedelta(minutes=45)
    client.post("/api/feed", json={"kind": "right", "at": hm(t)})
    assert hm(folke.parse(world.feedings()[0]["start"])) == hm(t)


# ---------- vækst ----------
def test_vaekst_gem_og_hent(client, world):
    birth = date.fromisoformat(world.birth())
    day = (birth + timedelta(days=91)).isoformat()
    assert client.post("/api/growth", json={"date": day, "w": "6,4", "l": 61.4}).status_code == 200
    d = client.get("/api/growth").get_json()
    [e] = d["entries"]
    assert e["w"] == 6.4 and e["h"] is None
    assert 40 <= e["pw"] <= 60 and e["ph"] is None
    assert set(d["curves"]) == {"w", "l", "h"}
    assert client.post(f"/api/growth/{e['id']}", json={"date": day, "w": 6.5}).status_code == 200
    assert client.get("/api/growth").get_json()["entries"][0]["w"] == 6.5
    assert client.delete(f"/api/growth/{e['id']}").status_code == 200
    assert client.get("/api/growth").get_json()["entries"] == []


@pytest.mark.parametrize("body", [
    {"date": "i går", "w": 5},
    {"date": (date.today() + timedelta(days=2)).isoformat(), "w": 5},
    {"date": "2026-01-01", "w": 50},
    {"date": "2026-01-01"},
])
def test_vaekst_ugyldig(client, body):
    assert client.post("/api/growth", json=body).status_code == 400


# ---------- forslag og tilpasning ----------
def test_forslag_fast_foede_ved_6_mdr(client, world):
    world.set_birth(now().date() - timedelta(days=200))
    sug = client.get("/api/status").get_json()["suggestions"]
    assert [s["id"] for s in sug] == ["solids"]
    assert client.post("/api/suggestion", json={"id": "solids", "answer": "yes"}).status_code == 200
    d = client.get("/api/status").get_json()
    assert d["features"]["solids"] is True and d["suggestions"] == []


def test_forslag_skjul_amning(client, world):
    world.add_feeding(now() - timedelta(days=30), method="left breast", type="breast milk")
    assert [s["id"] for s in client.get("/api/status").get_json()["suggestions"]] == ["hide_breast"]
    client.post("/api/suggestion", json={"id": "hide_breast", "answer": "later"})
    assert client.get("/api/status").get_json()["suggestions"] == []
    assert client.get("/api/status").get_json()["features"]["breast"] is True


def test_forslag_ugyldigt_svar(client):
    assert client.post("/api/suggestion", json={"id": "solids", "answer": "måske"}).status_code == 400


def test_feature_og_profil(client):
    assert client.post("/api/feature", json={"name": "solids", "on": True}).status_code == 200
    assert client.post("/api/feature", json={"name": "x"}).status_code == 400
    assert client.post("/api/profile", json={"sex": "girl"}).status_code == 200
    assert client.post("/api/profile", json={"sex": "x"}).status_code == 400
    d = client.get("/api/status").get_json()
    assert d["features"]["solids"] is True and d["sex"] == "girl"


def test_baby_buddy_fejl_giver_502(fake_bb, monkeypatch):
    import app as app_module
    import store

    monkeypatch.setattr(store, "_current", [store.BabyBuddy()])
    client = app_module.app.test_client()
    def boom(*a, **k):
        raise OSError("forbindelse nægtet")
    monkeypatch.setattr(folke, "call", boom)
    r = client.get("/api/status")
    assert r.status_code == 502 and "forbindelse" in r.get_json()["error"]
