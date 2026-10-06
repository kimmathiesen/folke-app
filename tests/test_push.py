"""Web push: nøgle, abonnementer, afsendelse (pywebpush erstattes) og notifikationer uden Home Assistant."""
import json
import os
from datetime import datetime, timedelta

import pytest
import pywebpush

import folke
import push

TZ = folke.TZ
SUB = {"endpoint": "https://web.push.apple.com/abc", "keys": {"p256dh": "BPk", "auth": "xyz"}}


class Calls(list):
    fail = None


class Resp:
    def __init__(self, code):
        self.status_code = code


@pytest.fixture
def sent(monkeypatch, tmp_path):
    monkeypatch.setattr(push, "KEY", str(tmp_path / "vapid.pem"))
    monkeypatch.setattr(push, "SUBS", str(tmp_path / "push.json"))
    monkeypatch.setattr(folke, "STATE_FILE", str(tmp_path / "state.json"))
    monkeypatch.setattr(folke, "HA_URL", "")
    monkeypatch.setattr(folke, "HA_NOTIFY", "")
    calls, fail = Calls(), {}

    def webpush(info, data, vapid_private_key=None, vapid_claims=None, **kw):
        if info["endpoint"] in fail:
            raise pywebpush.WebPushException("fejl", response=Resp(fail[info["endpoint"]]))
        calls.append((info["endpoint"], data, vapid_claims["sub"]))

    monkeypatch.setattr(pywebpush, "webpush", webpush)
    calls.fail = fail
    return calls


def test_noegle_laves_en_gang(client, sent):
    k1 = client.get("/api/push/key").get_json()["key"]
    assert len(k1) == 87 and "=" not in k1  # 65 bytes, base64url uden padding
    assert os.path.exists(push.KEY)
    assert client.get("/api/push/key").get_json()["key"] == k1


def test_abonner_og_afmeld(client, sent):
    assert client.post("/api/push/subscribe", json={"subscription": {"endpoint": "http://x"}}).status_code == 400
    r = client.post("/api/push/subscribe", json={"subscription": SUB, "origin": "https://folke.test", "name": "iPhone"})
    assert r.get_json() == {"ok": True, "devices": 1}
    client.post("/api/push/subscribe", json={"subscription": SUB, "origin": "https://folke.test"})
    assert len(push.load()) == 1  # samme enhed igen giver ingen dublet
    d = client.get("/api/status").get_json()
    assert d["push_devices"] == 1 and d["can_notify"] is True
    client.post("/api/push/unsubscribe", json={"endpoint": SUB["endpoint"]})
    assert push.load() == [] and client.get("/api/status").get_json()["can_notify"] is False


def test_send_fjerner_udloebne(sent):
    push.subscribe(SUB, "https://folke.test", "iPhone")
    push.subscribe({**SUB, "endpoint": "https://fcm.googleapis.com/gone"}, "http://lan:6661")
    push.subscribe({**SUB, "endpoint": "https://push.example/fejl"})
    sent.fail.update({"https://fcm.googleapis.com/gone": 410, "https://push.example/fejl": 500})
    assert push.send("Titel", "Tekst") == 1
    [(endpoint, data, sub)] = sent
    assert endpoint == SUB["endpoint"] and sub == "https://folke.test"
    assert json.loads(data) == {"title": "Titel", "body": "Tekst", "url": "/"}
    assert [s["endpoint"] for s in push.load()] == [SUB["endpoint"], "https://push.example/fejl"]  # 410 fjernet


def test_testbesked(client, sent):
    r = client.post("/api/push/test")
    assert r.status_code == 200 and r.get_json()["ok"] is False  # ingen enheder
    push.subscribe(SUB, "https://folke.test")
    assert client.post("/api/push/test").get_json() == {"ok": True, "sent": 1}


def test_vapid_sub_uden_https(sent):
    push.subscribe(SUB, "http://192.168.1.10:6661")
    push.send("a", "b")
    assert sent[0][2] == push.FALLBACK_SUB


def test_udpumpningspaamindelse_kun_via_push(client, world, sent):
    import app as app_module

    noon = datetime.now(TZ).replace(hour=12, minute=0, second=0, microsecond=0)
    t = noon - timedelta(hours=4)
    world.store.add_pumping(world.cid, start=t, end=t, amount=100)
    client.post("/api/pump/remind", json={"hours": 3})
    assert app_module.pump_reminder(noon) is False  # ingen kanal endnu
    push.subscribe(SUB, "https://folke.test")
    assert app_module.pump_reminder(noon) is False  # udpumpning er slået fra på nye enheder
    push.set_kinds(SUB["endpoint"], {"pump": True})
    assert app_module.pump_reminder(noon) is True
    assert "udpumpning" in json.loads(sent[0][1])["body"]


def test_naeste_soevn_via_push_uden_home_assistant(world, sent, real_main, noon):
    now = noon
    world.set_birth(now.date() - timedelta(days=150))  # 4,9 mdr.: standardvindue 120 min
    world.add_sleep(now - timedelta(hours=3), now - timedelta(minutes=115))  # næste søvn om ca. 5 min
    push.subscribe(SUB, "https://folke.test")
    real_main()
    assert len(sent) == 1 and json.loads(sent[0][1])["title"] == "Søvn"
    real_main()
    assert len(sent) == 1  # kun én gang pr. forudsigelse


def test_service_worker(client):
    r = client.get("/sw.js")
    assert r.status_code == 200 and "javascript" in r.content_type
    assert b"showNotification" in r.data and r.headers["Cache-Control"] == "no-cache"
