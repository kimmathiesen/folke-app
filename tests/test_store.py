"""SQLite-lageret: skema, tider, eksport, backup og folke.main()."""
import json
import os
import sqlite3
from datetime import datetime, timedelta

import pytest

import folke
import store
from conftest import EPOCH

TZ = folke.TZ


def now():
    return datetime.now(TZ).replace(microsecond=0)


@pytest.fixture
def db(tmp_path, monkeypatch):
    monkeypatch.setattr(store, "_current", [])
    return store.use(store.Sqlite(str(tmp_path / "folke.db")))


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
    assert folke.parse(row["start"]) == s.replace(microsecond=0)
    assert row["nap"] is True


def test_child_birth_fra_env(tmp_path, monkeypatch):
    monkeypatch.setenv("CHILD_BIRTH", "2026-02-01")
    monkeypatch.setenv("CHILD_NAME", "Folke")
    s = store.Sqlite(str(tmp_path / "x.db"))
    assert s.child()["birth_date"] == "2026-02-01"
    store.Sqlite(str(tmp_path / "x.db"))  # ikke to gange
    assert len(s._rows("SELECT * FROM child")) == 1


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


def test_eksport(db, app_client):
    assert app_client.get("/api/status").get_json()["setup"] is True  # intet barn endnu
    assert app_client.post("/api/child", json={"name": "Folke", "birth_date": (now() - timedelta(days=90)).date().isoformat()}).status_code == 200
    cid = db.child()["id"]
    db.add_sleep(cid, now() - timedelta(hours=5), now() - timedelta(hours=4), True)
    db.add_pumping(cid, start=now() - timedelta(hours=3), amount=80.0)
    db.add_pumping(cid, start=now() - timedelta(hours=2), amount=60.0)
    app_client.post("/api/growth", json={"date": now().date().isoformat(), "w": 6})
    r = app_client.get("/api/export")
    assert "attachment" in r.headers["Content-Disposition"]
    d = json.loads(r.data)
    assert len(d["sleep"]) == 1 and len(d["pumping"]) == 2 and d["growth"][0]["w"] == 6.0
    assert d["child"][0]["first_name"] == "Folke"


# ---------- folke.main() ----------
def test_main_opdaterer_valgt_sensor(db, real_main, monkeypatch):
    db._exec("INSERT INTO child (birth_date) VALUES (?)", ((now() - timedelta(days=100)).date().isoformat(),))
    db.add_sleep(1, now() - timedelta(hours=2), now() - timedelta(hours=1), True)
    sent = []
    monkeypatch.setattr(folke, "HA_URL", "http://ha.test")
    monkeypatch.setattr(folke, "HA_SENSOR", "sensor.folke_test")
    monkeypatch.setattr(folke, "call", lambda url, *a, **k: sent.append(url))
    real_main()
    assert sent == ["http://ha.test/api/states/sensor.folke_test"]
