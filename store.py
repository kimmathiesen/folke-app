"""Datalag: samme funktioner mod Baby Buddy (REST) eller en lokal SQLite-fil.

Vælges med BACKEND=babybuddy|sqlite (standard babybuddy). Tider returneres som ISO-tekst
(med tidszone), så resten af appen ikke kan se forskel. Søvn, timere, måltider og
pumpninger er dicts med samme felter som i Baby Buddys API.
"""
import glob
import os
import sqlite3
import urllib.parse
from datetime import date, datetime, timezone

import napper

TIMER = "Søvn"


def iso(t):
    """datetime eller ISO-tekst -> UTC-tekst med sekunder (ens format = kan sorteres som tekst)."""
    if isinstance(t, str):
        t = datetime.fromisoformat(t)
    return t.astimezone(timezone.utc).isoformat(timespec="seconds")


# ---------- Baby Buddy ----------
class BabyBuddy:
    name = "babybuddy"

    def _bb(self, path, method="GET", body=None):
        return napper.call(f"{napper.BB_URL}/api/{path}", napper.BB_TOKEN, method, body)

    @staticmethod
    def _q(t):
        return urllib.parse.quote(t.isoformat())

    def child(self):
        cs = napper.bb_all("children/")
        return next((c for c in cs if not napper.CHILD_ID or str(c["id"]) == napper.CHILD_ID), None)

    def sleeps(self, cid, since):
        raw = napper.bb_all(f"sleep/?child={cid}&start_min={self._q(since)}&limit=200")
        return [{"id": s["id"], "start": s["start"], "end": s["end"], "nap": s["nap"]}
                for s in raw if s.get("end")]

    def add_sleep(self, cid, start, end, nap):
        self._bb("sleep/", "POST", {"child": cid, "start": start.isoformat(), "end": end.isoformat(), "nap": nap})

    def edit_sleep(self, sid, start, end, nap=None):
        body = {"start": start.isoformat(), "end": end.isoformat()}
        if nap is not None:
            body["nap"] = bool(nap)
        self._bb(f"sleep/{sid}/", "PATCH", body)

    def delete_sleep(self, sid):
        self._bb(f"sleep/{sid}/", "DELETE")

    def timer(self, cid):
        return next((t for t in napper.bb_all(f"timers/?child={cid}") if t["name"] == TIMER), None)

    def start_timer(self, cid, start):
        self._bb("timers/", "POST", {"child": cid, "name": TIMER, "start": start.isoformat()})

    def delete_timer(self, tid):
        self._bb(f"timers/{tid}/", "DELETE")

    def feedings(self, cid, since):
        return napper.bb_all(f"feedings/?child={cid}&start_min={self._q(since)}&limit=200")

    def add_feeding(self, cid, **f):
        self._bb("feedings/", "POST", {"child": cid, **self._ser(f)})

    def pumpings(self, cid, since):
        return napper.bb_all(f"pumping/?child={cid}&start_min={self._q(since)}&limit=200")

    def add_pumping(self, cid, side=None, minutes=None, **p):
        # Baby Buddy har ingen felter til side og varighed
        self._bb("pumping/", "POST", {"child": cid, **self._ser(p)})

    def edit_pumping(self, pid, start, amount, side=None, minutes=None):
        self._bb(f"pumping/{pid}/", "PATCH", {"start": start.isoformat(), "end": start.isoformat(), "amount": amount})

    def delete_pumping(self, pid):
        self._bb(f"pumping/{pid}/", "DELETE")

    @staticmethod
    def _ser(d):
        return {k: v.isoformat() if isinstance(v, datetime) else v for k, v in d.items()}


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
    # Udpumpning: side (left/right/both) og varighed i minutter - findes ikke i Baby Buddy
    """
    ALTER TABLE pumping ADD COLUMN side TEXT;
    ALTER TABLE pumping ADD COLUMN minutes REAL;
    """,
]
TABLES = ("child", "sleep", "timer", "feeding", "pumping")


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

    def child(self):
        cs = self._rows("SELECT id, first_name, birth_date FROM child ORDER BY id")
        return next((c for c in cs if not napper.CHILD_ID or str(c["id"]) == napper.CHILD_ID), cs[0] if cs else None)

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
    def import_bb(self):
        """Envejs-import fra Baby Buddy. Kan køres igen: rækker matches på bb_id, rækker der er
        slettet i Baby Buddy fjernes også her, og alt oprettet lokalt (bb_id = NULL) røres ikke."""
        bb = BabyBuddy()
        child = bb.child()
        if not child:
            raise ValueError("Intet barn fundet i Baby Buddy")
        bid = child["id"]
        sources = {
            "sleep": [{"bb_id": s["id"], "start": iso(s["start"]), "end": iso(s["end"]), "nap": int(bool(s["nap"]))}
                      for s in napper.bb_all(f"sleep/?child={bid}&limit=1000") if s.get("end")],
            "timer": [{"bb_id": t["id"], "name": t["name"], "start": iso(t["start"])}
                      for t in napper.bb_all(f"timers/?child={bid}") if t.get("name") == TIMER and t.get("start")],
            "feeding": [{"bb_id": f["id"], "start": iso(f["start"]), "end": f.get("end") and iso(f["end"]),
                         "type": f.get("type"), "method": f.get("method"), "amount": f.get("amount"),
                         "notes": f.get("notes")}
                        for f in napper.bb_all(f"feedings/?child={bid}&limit=1000")],
            # Ældre Baby Buddy har "time" i stedet for start/end på pumpning
            "pumping": [{"bb_id": p["id"], "start": iso(p.get("start") or p["time"]),
                         "end": iso(p.get("end") or p.get("start") or p["time"]),
                         "amount": p.get("amount"), "notes": p.get("notes")}
                        for p in napper.bb_all(f"pumping/?child={bid}&limit=1000")],
        }
        db = self._db()
        counts = {}
        try:
            with db:
                db.execute("INSERT INTO child (bb_id, first_name, birth_date) VALUES (?, ?, ?) "
                           "ON CONFLICT(bb_id) DO UPDATE SET first_name = excluded.first_name, "
                           "birth_date = excluded.birth_date",
                           (bid, child.get("first_name", ""), child["birth_date"]))
                cid = db.execute("SELECT id FROM child WHERE bb_id = ?", (bid,)).fetchone()[0]
                for table, rows in sources.items():
                    for r in rows:
                        cols = ["child", *r]
                        q = ", ".join(f'"{c}"' for c in cols)
                        upd = ", ".join(f'"{c}" = excluded."{c}"' for c in r if c != "bb_id")
                        db.execute(f"INSERT INTO {table} ({q}) VALUES ({', '.join('?' * len(cols))}) "
                                   f"ON CONFLICT(bb_id) DO UPDATE SET {upd}", (cid, *r.values()))
                    keep = [r["bb_id"] for r in rows]
                    db.execute(f"DELETE FROM {table} WHERE child = ? AND bb_id IS NOT NULL "
                               f"AND bb_id NOT IN ({', '.join('?' * len(keep))})", (cid, *keep))
                    counts[table] = len(rows)
        finally:
            db.close()
        return {"child": child.get("first_name", ""), **counts}

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


# ---------- valg af backend ----------
_current = []


def get():
    if not _current:
        if os.environ.get("BACKEND", "babybuddy") == "sqlite":
            path = os.environ.get("DB_FILE") or os.path.join(os.path.dirname(napper.STATE_FILE) or ".", "folke.db")
            _current.append(Sqlite(path))
        else:
            _current.append(BabyBuddy())
    return _current[0]


def use(backend):
    """Skift backend (bruges af tests)."""
    _current[:] = [backend]
    return backend

