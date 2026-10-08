"""Fælles opsætning: miljøet sættes, før folke/app importeres (de læser env ved import)."""
import os
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

os.environ.update({
    "CHILD_ID": "",
    "TZ": "Europe/Copenhagen",
    "STATE_FILE": os.path.join(tempfile.mkdtemp(), "state.json"),
})
os.environ.pop("CHILD_BIRTH", None)

from datetime import datetime, timedelta, timezone  # noqa: E402

import pytest  # noqa: E402

import folke  # noqa: E402
import store  # noqa: E402

# app.py starter en baggrundstråd ved import, som kalder folke.main() - ingen netværk i tests
_real_main = folke.main
folke.main = lambda: None

EPOCH = datetime(2000, 1, 1, tzinfo=timezone.utc)


class _Noon(datetime):
    """Uret står på kl. 12 i dag, så beskedtestene ikke afhænger af, hvornår de køres
    (om aftenen bliver næste søvn ellers sengetid i stedet for en lur)."""

    @classmethod
    def now(cls, tz=None):
        return datetime.now(tz).replace(hour=12, minute=0, second=0, microsecond=0)


@pytest.fixture
def noon(monkeypatch):
    monkeypatch.setattr(folke, "datetime", _Noon)
    return _Noon.now(folke.TZ)


@pytest.fixture
def real_main():
    return _real_main


@pytest.fixture(autouse=True)
def no_network(monkeypatch):
    """Intet går på netværket i tests (web push erstattes i `sent`-fixturen i test_push)."""
    import urllib.request

    def urlopen(req, *a, **k):
        raise AssertionError(f"uventet netværkskald: {getattr(req, 'full_url', req)}")
    monkeypatch.setattr(urllib.request, "urlopen", urlopen)


class SqliteWorld:
    """Testdata i en frisk SQLite-fil."""

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


@pytest.fixture
def world(tmp_path, monkeypatch):
    import app as app_module

    monkeypatch.setattr(app_module, "PREFS", str(tmp_path / "prefs.json"))
    monkeypatch.setattr(app_module, "GROWTH", str(tmp_path / "growth.json"))
    app_module._sc.update(t=0, v=[])
    w = SqliteWorld(str(tmp_path / "folke.db"), datetime.now(folke.TZ).date() - timedelta(days=120))
    yield w
    store._current.clear()


@pytest.fixture
def client(world):
    import app as app_module

    return app_module.app.test_client()
