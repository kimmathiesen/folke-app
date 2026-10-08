"""Datalag: en lokal SQLite-fil (DB_FILE, standard folke.db ved STATE_FILE).

Tider gemmes som UTC-tekst (`iso()`), så de kan sammenlignes som tekst. Søvn, timere, måltider og
pumpninger er dicts med de samme felter, som Baby Buddy havde (appen startede oven på Baby Buddy;
kolonnen `bb_id` er rest fra importen og bruges ikke længere).
"""
import glob
import os
import sqlite3
from datetime import date, datetime, timezone

import folke

TIMER = "Søvn"


def iso(t):
    """datetime eller ISO-tekst -> UTC-tekst med sekunder (ens format = kan sorteres som tekst)."""
    if isinstance(t, str):
        t = datetime.fromisoformat(t)
    return t.astimezone(timezone.utc).isoformat(timespec="seconds")


# ---------- SQLite ----------
MIGRATIONS = [
    """
    CREATE TABLE child (id INTEGER PRIMARY KEY, bb_id INTEGER UNIQUE, first_name TEXT, birth_date TEXT NOT NULL);
    CREATE TABLE sleep (id INTEGER PRIMARY KEY, bb_id INTEGER UNIQUE, child INTEGER NOT NULL,
                        start TEXT NOT NULL, "end" TEXT NOT NULL, nap INTEGER NOT NULL);
    CREATE TABLE timer (id INTEGER PRIMARY KEY, bb_id INTEGER UNIQUE, child INTEGER NOT NULL,
                        name TEXT NOT NULL, start TEXT NOT NULL);
    CREATE TABLE feeding (id INTEGER PRIMARY KEY, bb_id INTEGER UNIQUE, child INTEGER NOT NULL,
                          start TEXT NOT NULL, "end" TEXT, type TEXT, method TEXT, amount REAL, notes TEXT);
    CREATE TABLE pumping (id INTEGER PRIMARY KEY, bb_id INTEGER UNIQUE, child INTEGER NOT NULL,
                          start TEXT NOT NULL, "end" TEXT, amount REAL, notes TEXT);
    CREATE INDEX sleep_start ON sleep (child, start);
    CREATE INDEX feeding_start ON feeding (child, start);
    CREATE INDEX pumping_start ON pumping (child, start);
    """,
    # Udpumpning: side (left/right/both) og varighed i minutter
    """
    ALTER TABLE pumping ADD COLUMN side TEXT;
    ALTER TABLE pumping ADD COLUMN minutes REAL;
    """,
    # Opvågninger om natten (end NULL = vågen nu). Hører til natten ud fra tidspunktet.
    """
    CREATE TABLE night_wake (id INTEGER PRIMARY KEY, child INTEGER NOT NULL, start TEXT NOT NULL, "end" TEXT);
    CREATE INDEX night_wake_start ON night_wake (child, start);
    """,
]
TABLES = ("child", "sleep", "timer", "feeding", "pumping", "night_wake")


class Sqlite:
    name = "sqlite"

    def __init__(self, path):
        self.path = path
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with self._db() as db:
            db.execute("PRAGMA journal_mode=WAL")
            v = db.execute("PRAGMA user_version").fetchone()[0]
            for i, sql in enumerate(MIGRATIONS[v:], v + 1):
                db.executescript(sql)
                db.execute(f"PRAGMA user_version = {i}")
        # Barn uden import: CHILD_BIRTH=YYYY-MM-DD (og evt. CHILD_NAME)
        birth = os.environ.get("CHILD_BIRTH")
        if birth and not self.child():
            date.fromisoformat(birth)
            self._exec("INSERT INTO child (first_name, birth_date) VALUES (?, ?)",
                       (os.environ.get("CHILD_NAME", ""), birth))

    def _db(self):
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        return db

    def _exec(self, sql, args=()):
        db = self._db()
        try:
            with db:
                return db.execute(sql, args).lastrowid
        finally:
            db.close()

    def _rows(self, sql, args=()):
        db = self._db()
        try:
            return [dict(r) for r in db.execute(sql, args)]
        finally:
            db.close()

    def add_child(self, name, birth):
        self._exec("INSERT INTO child (first_name, birth_date) VALUES (?, ?)", (name, birth.isoformat()))

    def child(self):
        cs = self._rows("SELECT id, first_name, birth_date FROM child ORDER BY id")
        return next((c for c in cs if not folke.CHILD_ID or str(c["id"]) == folke.CHILD_ID), cs[0] if cs else None)

    def sleeps(self, cid, since):
        rows = self._rows('SELECT id, start, "end", nap FROM sleep WHERE child = ? AND start >= ? ORDER BY start',
                          (cid, iso(since)))
        return [{**r, "nap": bool(r["nap"])} for r in rows]

    def add_sleep(self, cid, start, end, nap):
        self._exec('INSERT INTO sleep (child, start, "end", nap) VALUES (?, ?, ?, ?)',
                   (cid, iso(start), iso(end), int(bool(nap))))

    def edit_sleep(self, sid, start, end, nap=None):
        if nap is None:
            self._exec('UPDATE sleep SET start = ?, "end" = ? WHERE id = ?', (iso(start), iso(end), sid))
        else:
            self._exec('UPDATE sleep SET start = ?, "end" = ?, nap = ? WHERE id = ?',
                       (iso(start), iso(end), int(bool(nap)), sid))

    def delete_sleep(self, sid):
        self._exec("DELETE FROM sleep WHERE id = ?", (sid,))

    def timer(self, cid):
        rows = self._rows("SELECT id, name, start FROM timer WHERE child = ? AND name = ?", (cid, TIMER))
        return rows[0] if rows else None

    def start_timer(self, cid, start):
        self._exec("INSERT INTO timer (child, name, start) VALUES (?, ?, ?)", (cid, TIMER, iso(start)))

    def delete_timer(self, tid):
        self._exec("DELETE FROM timer WHERE id = ?", (tid,))

    def wakes(self, cid, since):
        return self._rows('SELECT id, start, "end" FROM night_wake WHERE child = ? AND start >= ? ORDER BY start',
                          (cid, iso(since)))

    def open_wake(self, cid):
        rows = self._rows('SELECT id, start, "end" FROM night_wake WHERE child = ? AND "end" IS NULL', (cid,))
        return rows[0] if rows else None

    def add_wake(self, cid, start):
        self._exec("INSERT INTO night_wake (child, start) VALUES (?, ?)", (cid, iso(start)))

    def end_wake(self, wid, end):
        self._exec('UPDATE night_wake SET "end" = ? WHERE id = ?', (iso(end), wid))

    def delete_wake(self, wid):
        self._exec("DELETE FROM night_wake WHERE id = ?", (wid,))

    def delete_wakes_between(self, cid, start, end):
        self._exec("DELETE FROM night_wake WHERE child = ? AND start >= ? AND start <= ?", (cid, iso(start), iso(end)))

    def feedings(self, cid, since):
        return self._rows('SELECT id, start, "end", type, method, amount, notes FROM feeding '
                          "WHERE child = ? AND start >= ? ORDER BY start", (cid, iso(since)))

    def add_feeding(self, cid, start, end=None, type=None, method=None, amount=None, notes=None):
        self._exec('INSERT INTO feeding (child, start, "end", type, method, amount, notes) VALUES (?, ?, ?, ?, ?, ?, ?)',
                   (cid, iso(start), end and iso(end), type, method, amount, notes))

    def pumpings(self, cid, since):
        return self._rows('SELECT id, start, "end", amount, notes, side, minutes FROM pumping '
                          "WHERE child = ? AND start >= ? ORDER BY start", (cid, iso(since)))

    def add_pumping(self, cid, start, end=None, amount=None, notes=None, side=None, minutes=None):
        self._exec('INSERT INTO pumping (child, start, "end", amount, notes, side, minutes) VALUES (?, ?, ?, ?, ?, ?, ?)',
                   (cid, iso(start), end and iso(end), amount, notes, side, minutes))

    def edit_pumping(self, pid, start, amount, side=None, minutes=None):
        self._exec('UPDATE pumping SET start = ?, "end" = ?, amount = ?, side = ?, minutes = ? WHERE id = ?',
                   (iso(start), iso(start), amount, side, minutes, pid))

    def delete_pumping(self, pid):
        self._exec("DELETE FROM pumping WHERE id = ?", (pid,))

    # ---------- import / eksport / backup ----------
    def export(self):
        return {t: self._rows(f"SELECT * FROM {t} ORDER BY id") for t in TABLES}

    def backup(self, folder, keep=14):
        """Dagligt øjebliksbillede (folke-YYYY-MM-DD.db), de nyeste `keep` beholdes."""
        os.makedirs(folder, exist_ok=True)
        target = os.path.join(folder, f"folke-{date.today().isoformat()}.db")
        if os.path.exists(target):
            return None
        src, dst = self._db(), sqlite3.connect(target)
        try:
            src.backup(dst)
        finally:
            src.close()
            dst.close()
        for old in sorted(glob.glob(os.path.join(folder, "folke-*.db")))[:-keep]:
            os.remove(old)
        return target


# ---------- databasen ----------
_current = []


def get():
    if not _current:
        path = os.environ.get("DB_FILE") or os.path.join(os.path.dirname(folke.STATE_FILE) or ".", "folke.db")
        _current.append(Sqlite(path))
    return _current[0]


def use(backend):
    """Skift backend (bruges af tests)."""
    _current[:] = [backend]
    return backend

