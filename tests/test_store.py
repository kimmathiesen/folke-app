"""SQLite-lageret: import fra Baby Buddy, eksport, backup, skema og napper.main() uden Baby Buddy."""
import json
import os
import sqlite3
from datetime import datetime, timedelta

import pytest

import napper
import store
from conftest import EPOCH

TZ = napper.TZ


def now():
    return datetime.now(TZ).replace(microsecond=0)


@pytest.fixture
def db(tmp_path, monkeypatch):
    monkeypatch.setattr(store, "_current", [])
    return store.use(store.Sqlite(str(tmp_path / "folke.db")))


def seed(fake):
    t = now()
    fake.add("sleep", start=(t - timedelta(hours=5)).isoformat(), end=(t - timedelta(hours=4)).isoformat(), nap=True)
    fake.add("sleep", start=(t - timedelta(hours=2)).isoformat(), end=None, nap=True)  # ufærdig: springes over
    fake.add("timers", name="Søvn", start=(t - timedelta(minutes=10)).isoformat())
    fake.add("timers", name="Mad", start=(t - timedelta(minutes=5)).isoformat())
    fake.add("feedings", start=(t - timedelta(hours=1)).isoformat(), end=(t - timedelta(hours=1)).isoformat(),
             type="breast milk", method="left breast", amount=None)
    fake.add("pumping", time=(t - timedelta(hours=3)).isoformat(), amount=80.0)  # ældre Baby Buddy-format
    fake.add("pumping", start=(t - timedelta(hours=2)).isoformat(), end=(t - timedelta(hours=2)).isoformat(),
             amount=60.0)
    return t


def test_skema_og_version(db):
    con = sqlite3.connect(db.path)
    assert con.execute("PRAGMA user_version").fetchone()[0] == len(store.MIGRATIONS)
    tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    assert set(store.TABLES) <= tables
    con.close()
    store.Sqlite(db.path)  # åbne igen kører ikke migreringer to gange


def test_tider_gemmes_i_utc(db):
    db._exec("INSERT INTO child (birth_date) VALUES ('2026-01-01')")
    s = datetime(2026, 6, 1, 13, 0, 30, 123456, tzinfo=TZ)
    db.add_sleep(1, s, s + timedelta(hours=1), True)
    [row] = db.sleeps(1, EPOCH)
    assert row["start"] == "2026-06-01T11:00:30+00:00"
    assert napper.parse(row["start"]) == s.replace(microsecond=0)
    assert row["nap"] is True


def test_child_birth_fra_env(tmp_path, monkeypatch):
    monkeypatch.setenv("CHILD_BIRTH", "2026-02-01")
    monkeypatch.setenv("CHILD_NAME", "Folke")
    s = store.Sqlite(str(tmp_path / "x.db"))
    assert s.child()["birth_date"] == "2026-02-01"
    store.Sqlite(str(tmp_path / "x.db"))  # ikke to gange
    assert len(s._rows("SELECT * FROM child")) == 1


def test_import(db, fake_bb):
    t = seed(fake_bb)
    res = db.import_bb()
    assert res == {"child": "Folke", "sleep": 1, "timer": 1, "feeding": 1, "pumping": 2}
    c = db.child()
    assert c["birth_date"] == fake_bb.db["children"][0]["birth_date"]
    [s] = db.sleeps(c["id"], EPOCH)
    assert napper.parse(s["end"]) == t - timedelta(hours=4)
    assert napper.parse(db.timer(c["id"])["start"]) == t - timedelta(minutes=10)
    assert db.feedings(c["id"], EPOCH)[0]["method"] == "left breast"
    assert sorted(p["amount"] for p in db.pumpings(c["id"], EPOCH)) == [60.0, 80.0]


def test_import_igen_er_spejl_af_baby_buddy(db, fake_bb):
    seed(fake_bb)
    db.import_bb()
    cid = db.child()["id"]
    db.add_sleep(cid, now() - timedelta(hours=1), now(), True)  # oprettet lokalt
    assert db.import_bb()["sleep"] == 1
    assert len(db.sleeps(cid, EPOCH)) == 2  # ingen dubletter

    # Ret og slet i Baby Buddy, og importér igen
    fake_bb.db["sleep"][0]["nap"] = False
    fake_bb.db["timers"] = [t for t in fake_bb.db["timers"] if t["name"] != "Søvn"]
    fake_bb.db["feedings"] = []
    db.import_bb()
    sleeps = db.sleeps(cid, EPOCH)
    assert [s["nap"] for s in sleeps] == [False, True]  # den lokale er urørt
    assert db.timer(cid) is None
    assert db.feedings(cid, EPOCH) == []


def test_import_uden_barn(db, fake_bb):
    fake_bb.db["children"] = []
    with pytest.raises(ValueError):
        db.import_bb()


def test_backup_roterer(db, tmp_path):
    folder = tmp_path / "backup"
    folder.mkdir()
    for i in range(1, 20):
        (folder / f"folke-2025-01-{i:02d}.db").write_bytes(b"")
    target = db.backup(str(folder), keep=5)
    assert os.path.basename(target).startswith("folke-")
    assert db.backup(str(folder), keep=5) is None  # én pr. dag
    files = sorted(os.listdir(folder))
    assert len(files) == 5 and os.path.basename(target) in files
    con = sqlite3.connect(target)
    assert con.execute("PRAGMA user_version").fetchone()[0] == len(store.MIGRATIONS)
    con.close()


# ---------- endpoints ----------
@pytest.fixture
def app_client(tmp_path, monkeypatch):
    import app as app_module

    monkeypatch.setattr(app_module, "PREFS", str(tmp_path / "prefs.json"))
    monkeypatch.setattr(app_module, "GROWTH", str(tmp_path / "growth.json"))
    app_module._sc.update(t=0, v=[])
    return app_module.app.test_client()


def test_import_endpoint(db, fake_bb, app_client):
    assert app_client.get("/api/status").get_json()["setup"] is True  # intet barn endnu
    seed(fake_bb)
    r = app_client.post("/api/import")
    assert r.status_code == 200 and r.get_json()["sleep"] == 1
    d = app_client.get("/api/status").get_json()
    assert d["backend"] == "sqlite" and d["can_import"] is True
    assert d["sleeping"] is True  # den importerede timer


def test_eksport(db, fake_bb, app_client):
    seed(fake_bb)
    app_client.post("/api/import")
    app_client.post("/api/growth", json={"date": now().date().isoformat(), "w": 6})
    r = app_client.get("/api/export")
    assert "attachment" in r.headers["Content-Disposition"]
    d = json.loads(r.data)
    assert len(d["sleep"]) == 1 and len(d["pumping"]) == 2 and d["growth"][0]["w"] == 6.0
    assert d["child"][0]["first_name"] == "Folke"


def test_import_og_eksport_kraever_sqlite(fake_bb, app_client, monkeypatch):
    monkeypatch.setattr(store, "_current", [store.BabyBuddy()])
    assert app_client.post("/api/import").status_code == 400
    assert app_client.get("/api/export").status_code == 400


# ---------- napper.main() uden Baby Buddy ----------
def test_main_med_sqlite_opdaterer_valgt_sensor(db, fake_bb, real_main, monkeypatch):
    db._exec("INSERT INTO child (birth_date) VALUES (?)", ((now() - timedelta(days=100)).date().isoformat(),))
    db.add_sleep(1, now() - timedelta(hours=2), now() - timedelta(hours=1), True)
    sent = []
    monkeypatch.setattr(napper, "HA_URL", "http://ha.test")
    monkeypatch.setattr(napper, "HA_SENSOR", "sensor.folke_test")
    monkeypatch.setattr(napper, "call", lambda url, *a, **k: sent.append(url))
    real_main()
    assert sent == ["http://ha.test/api/states/sensor.folke_test"]  # og intet kald til Baby Buddy


def test_tick_importerer_tom_database_en_gang(db, fake_bb, monkeypatch):
    import app as app_module

    seed(fake_bb)
    app_module.tick()
    assert db.child()["first_name"] == "Folke"
    assert len(db.sleeps(db.child()["id"], EPOCH)) == 1
    calls = len(fake_bb.calls)
    app_module.tick()
    assert len(fake_bb.calls) == calls  # importerer ikke igen af sig selv
