"""Beskeder om søvn (30 min før / frisk efter lurtid), beskedtyper pr. enhed, barnets navn og opsætning."""
import json
from datetime import datetime, timedelta

import pytest

import folke
import push
from test_push import SUB, sent  # noqa: F401 (fixture)

TZ = folke.TZ
SUB2 = {**SUB, "endpoint": "https://web.push.apple.com/far"}


def bodies(sent):
    return [json.loads(d)["body"] for _, d, _ in sent]


@pytest.fixture(autouse=True)
def _noon(noon):
    """Alle beskedtests kører kl. 12, hvor næste søvn er en lur (se `noon` i conftest)."""


def due_in(world, minutes):
    """Ét søvn, så næste forventede søvn er om `minutes` min (aldersstandard 120 min ved 4,9 mdr.)."""
    now = folke.datetime.now(TZ)
    world.set_birth(now.date() - timedelta(days=150))
    world.add_sleep(now - timedelta(hours=3), now - timedelta(minutes=120 - minutes))


def test_besked_30_min_foer(client, world, sent, real_main):  # noqa: F811
    due_in(world, 25)
    push.subscribe(SUB, "https://folke.test")
    real_main()
    [b] = bodies(sent)
    assert b.startswith("Tid til at slappe af. ") and " ca. kl. " in b
    real_main()  # og ikke igen (heller ikke 10 min før)
    assert len(sent) == 1


def test_ingen_besked_tidligere_end_30_min(client, world, sent, real_main):  # noqa: F811
    due_in(world, 45)
    push.subscribe(SUB, "https://folke.test")
    real_main()
    assert sent == []


def test_frisk_efter_lurtid_med_navn(client, world, sent, real_main):  # noqa: F811
    client.post("/api/profile", json={"name": "Folke"})
    due_in(world, -20)
    push.subscribe(SUB, "https://folke.test")
    real_main()
    [b] = bodies(sent)
    assert b.startswith("Folke virker meget frisk. Prøv alligevel ")
    real_main()
    assert len(sent) == 1


@pytest.mark.parametrize("minutes", [-5, -150])
def test_ingen_frisk_besked_for_tidligt_eller_for_sent(client, world, sent, real_main, minutes):  # noqa: F811
    due_in(world, minutes)
    push.subscribe(SUB, "https://folke.test")
    real_main()
    assert sent == []


def test_ingen_besked_naar_han_sover(client, world, sent, real_main):  # noqa: F811
    due_in(world, -20)
    world.add_timer(folke.datetime.now(TZ) - timedelta(minutes=5))
    push.subscribe(SUB, "https://folke.test")
    real_main()
    assert sent == []


def test_beskedtyper_pr_enhed(client, world, sent, real_main):  # noqa: F811
    push.subscribe(SUB, "https://folke.test", "Mors iPhone")
    push.subscribe(SUB2, "https://folke.test", "Fars iPhone")
    r = client.post("/api/push/kinds", json={"endpoint": SUB["endpoint"]})
    assert r.get_json()["kinds"] == {"sleep_soon": True, "overdue": True, "pump": False}  # standard
    client.post("/api/push/kinds", json={"endpoint": SUB2["endpoint"], "kinds": {"overdue": False, "x": True}})
    assert push.kinds(SUB2["endpoint"]) == {"sleep_soon": True, "overdue": False, "pump": False}
    due_in(world, -20)
    real_main()
    assert [e for e, _, _ in sent] == [SUB["endpoint"]]  # far har slået «frisk» fra
    assert client.post("/api/push/kinds", json={"endpoint": "https://ukendt"}).status_code == 404


def test_minutter_pr_enhed(client, world, sent, real_main, monkeypatch):  # noqa: F811
    push.subscribe(SUB, "https://folke.test", "Mors iPhone")
    push.subscribe(SUB2, "https://folke.test", "Fars iPhone")
    r = client.post("/api/push/kinds", json={"endpoint": SUB["endpoint"], "minutes": {"lead": 20}})
    assert r.get_json()["minutes"] == {"lead": 20, "overdue": 15}
    assert r.get_json()["options"]["lead"] == [10, 15, 20, 30, 45, 60]
    due_in(world, 25)  # 25 min før: kun far (30 min) får besked
    real_main()
    assert [e for e, _, _ in sent] == [SUB2["endpoint"]]
    monkeypatch.setattr(folke, "datetime", type("Later", (folke.datetime,), {"now": classmethod(
        lambda cls, tz=None: datetime.now(tz).replace(hour=12, minute=10, second=0, microsecond=0))}))
    real_main()  # 15 min før: nu mor, og far får den ikke igen
    assert [e for e, _, _ in sent] == [SUB2["endpoint"], SUB["endpoint"]]


def test_ugyldige_minutter(client, sent):  # noqa: F811
    push.subscribe(SUB, "https://folke.test")
    r = client.post("/api/push/kinds", json={"endpoint": SUB["endpoint"], "minutes": {"lead": 7}})
    assert r.status_code == 400
    assert client.post("/api/push/kinds", json={"endpoint": SUB["endpoint"], "minutes": {"x": 10}}).status_code == 400
    assert push.minutes(SUB["endpoint"]) == {"lead": 30, "overdue": 15}


def test_ingen_dobbelt_besked_efter_opdatering(client, world, sent, real_main):  # noqa: F811
    """Fra før minutter pr. enhed huskede serveren kun én fælles «notified». Den tæller stadig."""
    due_in(world, 25)
    push.subscribe(SUB, "https://folke.test")
    real_main()
    state = folke.load_state()
    [dev] = state.pop("push_sent").values()
    state["notified"] = dev["sleep_soon"]  # som en gammel state.json
    folke.save_state(state)
    n = len(sent)
    real_main()
    assert len(sent) == n


def test_valg_bevares_ved_ny_tilmelding(sent):  # noqa: F811
    push.subscribe(SUB, "https://folke.test")
    push.set_kinds(SUB["endpoint"], {"pump": True})
    push.subscribe(SUB, "https://folke.test", "Mors iPhone")
    assert push.kinds(SUB["endpoint"])["pump"] is True and len(push.load()) == 1


# ---------- navn og opsætning ----------
def test_barnets_navn(client, world):
    assert client.post("/api/profile", json={"name": "  "}).status_code == 400
    assert client.post("/api/profile", json={"name": "x" * 41}).status_code == 400
    assert client.post("/api/profile", json={"name": " Folke  Emil "}).status_code == 200
    d = client.get("/api/status").get_json()
    assert d["child_name"] == "Folke Emil" and d["sex"] == "boy"  # køn er uændret


def test_opsaetning_uden_import(tmp_path, monkeypatch):
    import app as app_module
    import store

    monkeypatch.setattr(store, "_current", [store.Sqlite(str(tmp_path / "ny.db"))])
    monkeypatch.setattr(app_module, "PREFS", str(tmp_path / "prefs.json"))
    c = app_module.app.test_client()
    assert c.get("/api/status").get_json()["setup"] is True
    today = datetime.now(TZ).date()
    assert c.post("/api/child", json={"name": "Folke", "birth_date": "i går"}).status_code == 400
    assert c.post("/api/child", json={"name": "Folke", "birth_date": (today + timedelta(days=1)).isoformat()}).status_code == 400
    assert c.post("/api/child", json={"name": "", "birth_date": today.isoformat()}).status_code == 400
    assert c.post("/api/child", json={"name": "Folke", "birth_date": (today - timedelta(days=30)).isoformat()}).status_code == 200
    d = c.get("/api/status").get_json()
    assert "setup" not in d and d["child_name"] == "Folke"
    assert c.post("/api/child", json={"name": "X", "birth_date": today.isoformat()}).status_code == 409
