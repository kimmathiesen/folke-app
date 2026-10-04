"""Fælles opsætning: miljøet sættes, før napper/app importeres (de læser env ved import)."""
import os
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

os.environ.update({
    "BACKEND": "babybuddy",
    "BB_URL": "http://bb.test",
    "BB_TOKEN": "test",
    "HA_URL": "",
    "HA_NOTIFY": "",
    "CHILD_ID": "",
    "TZ": "Europe/Copenhagen",
    "STATE_FILE": os.path.join(tempfile.mkdtemp(), "state.json"),
})
os.environ.pop("CHILD_BIRTH", None)

from datetime import datetime, timedelta, timezone  # noqa: E402

import pytest  # noqa: E402

import napper  # noqa: E402
import store  # noqa: E402

# app.py starter en baggrundstråd ved import, som kalder napper.main() - ingen netværk i tests
_real_main = napper.main
napper.main = lambda: None

from fakebb import FakeBB  # noqa: E402

EPOCH = datetime(2000, 1, 1, tzinfo=timezone.utc)


@pytest.fixture
def real_main():
    return _real_main


@pytest.fixture
def fake_bb(monkeypatch):
    fake = FakeBB(birth=datetime.now(napper.TZ).date() - timedelta(days=120))
    monkeypatch.setattr(napper, "call", fake)
    return fake


class BBWorld:
    """Testdata direkte i den falske Baby Buddy."""

    def __init__(self, fake):
        self.fake = fake
        self.store = store.use(store.BabyBuddy())

    def add_sleep(self, start, end, nap=True):
        return self.fake.add("sleep", start=start.isoformat(), end=end.isoformat(), nap=nap)["id"]

    def add_timer(self, start):
        return self.fake.add("timers", name=store.TIMER, start=start.isoformat())["id"]

    def add_feeding(self, start, **f):
        self.fake.add("feedings", start=start.isoformat(), **f)

    def set_birth(self, d):
        self.fake.db["children"][0]["birth_date"] = d.isoformat()

    def birth(self):
        return self.fake.db["children"][0]["birth_date"]

    def timers(self):
        return self.fake.db["timers"]

    def sleeps(self):
        return self.fake.db["sleep"]

    def feedings(self):
        return self.fake.db["feedings"]

    def pumpings(self):
        return self.fake.db["pumping"]


class SqliteWorld:
    """Testdata i en frisk SQLite-fil. Den falske Baby Buddy er tom og må ikke blive brugt."""

    def __init__(self, path, birth):
        self.store = store.use(store.Sqlite(path))
        self.store._exec("INSERT INTO child (first_name, birth_date) VALUES ('Folke', ?)", (birth.isoformat(),))
        self.cid = self.store.child()["id"]

    def add_sleep(self, start, end, nap=True):
        self.store.add_sleep(self.cid, start, end, nap)
        return self.store._rows("SELECT max(id) AS id FROM sleep")[0]["id"]

    def add_timer(self, start):
        self.store.start_timer(self.cid, start)
        return self.store.timer(self.cid)["id"]

    def add_feeding(self, start, **f):
        self.store.add_feeding(self.cid, start=start, **f)

    def set_birth(self, d):
        self.store._exec("UPDATE child SET birth_date = ?", (d.isoformat(),))

    def birth(self):
        return self.store.child()["birth_date"]

    def timers(self):
        t = self.store.timer(self.cid)
        return [t] if t else []

    def sleeps(self):
        return self.store.sleeps(self.cid, EPOCH)

    def feedings(self):
        return self.store.feedings(self.cid, EPOCH)

    def pumpings(self):
        return self.store.pumpings(self.cid, EPOCH)


@pytest.fixture(params=["babybuddy", "sqlite"])
def world(request, fake_bb, tmp_path, monkeypatch):
    import app as app_module

    monkeypatch.setattr(app_module, "PREFS", str(tmp_path / "prefs.json"))
    monkeypatch.setattr(app_module, "GROWTH", str(tmp_path / "growth.json"))
    app_module._sc.update(t=0, v=[])
    if request.param == "babybuddy":
        w = BBWorld(fake_bb)
    else:
        fake_bb.db["children"] = []  # SQLite-testene må ikke ramme Baby Buddy
        w = SqliteWorld(str(tmp_path / "folke.db"), datetime.now(napper.TZ).date() - timedelta(days=120))
    yield w
    store._current.clear()


@pytest.fixture
def client(world):
    import app as app_module

    return app_module.app.test_client()
