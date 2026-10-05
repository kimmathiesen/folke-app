"""Udpumpning: registrering, ret/slet, dagsoversigt, historik og påmindelse - mod begge backends."""
from datetime import datetime, timedelta

import pytest

import napper

TZ = napper.TZ


def now():
    return datetime.now(TZ).replace(second=0, microsecond=0)


def hm(t):
    return f"{t:%H:%M}"


def test_registrer_med_tid_side_og_minutter(client, world):
    t = now() - timedelta(minutes=40)
    r = client.post("/api/pump", json={"amount": "120,5", "at": hm(t), "side": "left", "minutes": 15})
    assert r.get_json() == {"ok": True, "amount": 120.5}
    [p] = world.pumpings()
    assert p["amount"] == 120.5 and napper.parse(p["start"]) == t
    if world.store.name == "sqlite":  # Baby Buddy kan ikke gemme side og varighed
        assert p["side"] == "left" and p["minutes"] == 15


def test_home_assistant_format_virker_stadig(client, world):
    assert client.post("/api/pump", json={"amount": 90}).status_code == 200
    assert world.pumpings()[0]["amount"] == 90


@pytest.mark.parametrize("body", [{"amount": 0}, {"amount": 50, "side": "midt"}, {"amount": 50, "minutes": 500},
                                  {"amount": 50, "minutes": "x"}, {"amount": 50, "at": "kl. 3"}])
def test_ugyldig(client, world, body):
    r = client.post("/api/pump", json=body)
    assert r.status_code == 400 and "invalid" not in r.get_json()["error"].lower()
    assert world.pumpings() == []


def test_ret_og_slet(client, world):
    client.post("/api/pump", json={"amount": 100})
    pid = world.pumpings()[0]["id"]
    y = (now() - timedelta(days=1)).date()
    r = client.post(f"/api/pump/{pid}", json={"start": f"{y}T08:30", "amount": 140, "side": "both", "minutes": 20})
    assert r.status_code == 200
    [p] = world.pumpings()
    assert p["amount"] == 140
    assert napper.parse(p["start"]) == datetime.fromisoformat(f"{y}T08:30").replace(tzinfo=TZ)
    if world.store.name == "sqlite":
        assert p["side"] == "both" and p["minutes"] == 20
    assert client.post(f"/api/pump/{pid}", json={"start": "x", "amount": 1}).status_code == 400
    future = (now() + timedelta(days=1)).strftime("%Y-%m-%dT%H:%M")
    assert client.post(f"/api/pump/{pid}", json={"start": future, "amount": 1}).status_code == 400
    assert client.delete(f"/api/pump/{pid}").status_code == 200
    assert world.pumpings() == []


def test_status_viser_dagens_total(client, world):
    t = now()
    world.store.add_pumping(world.cid, start=t - timedelta(days=1), end=t - timedelta(days=1), amount=999)
    world.store.add_pumping(world.cid, start=t - timedelta(minutes=5), end=t - timedelta(minutes=5), amount=80)
    world.store.add_pumping(world.cid, start=t - timedelta(minutes=1), end=t - timedelta(minutes=1), amount=70)
    p = client.get("/api/status").get_json()["pump"]
    if (t - timedelta(minutes=5)).date() == t.date():  # ikke lige efter midnat
        assert p["today_ml"] == 150 and p["today_count"] == 2
    assert p["last"]["amount"] == 70


def test_historik_pr_dag(client, world):
    today = now().replace(hour=12, minute=0)
    for ago, ml in [(timedelta(0), 50), (timedelta(days=1), 100), (timedelta(days=1, hours=-1), 120),
                    (timedelta(days=3), 200), (timedelta(days=20), 999)]:
        t = today - ago
        world.store.add_pumping(world.cid, start=t, end=t, amount=ml)
    d = client.get("/api/pump/history?days=7").get_json()
    assert len(d["days"]) == 7 and d["days"][-1]["date"] == today.date().isoformat()
    by = {x["date"]: x for x in d["days"]}
    assert by[today.date().isoformat()]["ml"] == 50
    assert by[(today - timedelta(days=1)).date().isoformat()] == {
        "date": (today - timedelta(days=1)).date().isoformat(), "ml": 220, "count": 2}
    assert d["avg_ml"] == 210  # gennemsnit af hele dage med udpumpning (220 og 200), ikke i dag
    assert [i["amount"] for i in d["items"]] == [50, 120, 100, 200]  # nyeste først, 20 dage gammel er udenfor
    assert d["detail"] == (world.store.name == "sqlite")


def test_paamindelse_indstilling(client):
    assert client.post("/api/pump/remind", json={"hours": 3}).status_code == 200
    assert client.get("/api/status").get_json()["pump_remind"] == 3
    assert client.post("/api/pump/remind", json={"hours": 30}).status_code == 400
    assert client.post("/api/feature", json={"name": "pump", "on": False}).status_code == 200
    assert client.get("/api/status").get_json()["features"]["pump"] is False


@pytest.fixture
def ha(monkeypatch, tmp_path):
    sent = []
    monkeypatch.setattr(napper, "HA_URL", "http://ha.test")
    monkeypatch.setattr(napper, "HA_NOTIFY", "notify.mobile_app_test")
    monkeypatch.setattr(napper, "STATE_FILE", str(tmp_path / "state.json"))
    monkeypatch.setattr(napper, "notify", lambda title, msg, kind=None: sent.append((title, msg)))
    return sent


def test_paamindelse(client, world, ha, monkeypatch):
    import app as app_module

    noon = now().replace(hour=12, minute=0)
    t = noon - timedelta(hours=4)
    world.store.add_pumping(world.cid, start=t, end=t, amount=100)
    assert app_module.pump_reminder(noon) is False  # Home Assistant får ikke udpumpning som standard
    monkeypatch.setattr(napper, "HA_KINDS", ["sleep_soon", "overdue", "pump"])
    client.post("/api/pump/remind", json={"hours": 5})
    assert app_module.pump_reminder(noon) is False  # kun 4 timer siden
    client.post("/api/pump/remind", json={"hours": 3})
    assert app_module.pump_reminder(noon) is True
    assert ha == [("Udpumpning", "Det er 4 timer siden sidste udpumpning (kl. 08:00)")]
    assert app_module.pump_reminder(noon + timedelta(minutes=1)) is False  # kun én gang
    assert len(ha) == 1


def test_paamindelse_ikke_om_natten_eller_naar_slaaet_fra(client, world, ha):
    import app as app_module

    night = now().replace(hour=23, minute=0)
    t = night - timedelta(hours=6)
    world.store.add_pumping(world.cid, start=t, end=t, amount=100)
    client.post("/api/pump/remind", json={"hours": 3})
    assert app_module.pump_reminder(night) is False
    client.post("/api/feature", json={"name": "pump", "on": False})
    assert app_module.pump_reminder(night.replace(hour=21)) is False
    assert ha == []
