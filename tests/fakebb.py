"""Falsk Baby Buddy i hukommelsen. Erstatter napper.call, så intet går på netværket."""
import urllib.parse
from datetime import datetime

import napper


class FakeBB:
    """Minimal Baby Buddy i hukommelsen: GET-lister (child/start_min), POST, PATCH og DELETE."""

    def __init__(self, birth):
        self.db = {"children": [{"id": 1, "first_name": "Folke", "birth_date": birth.isoformat()}],
                   "timers": [], "sleep": [], "feedings": [], "pumping": []}
        self.next_id = 100
        self.calls = []

    def add(self, coll, **row):
        row = {"id": self.next_id, "child": 1, **row}
        self.next_id += 1
        self.db[coll].append(row)
        return row

    def __call__(self, url, token, method="GET", body=None, scheme="Token"):
        u = urllib.parse.urlsplit(url)
        assert url.startswith(napper.BB_URL + "/api/"), url
        parts = [p for p in u.path.split("/")[2:] if p]
        q = dict(urllib.parse.parse_qsl(u.query))
        self.calls.append((method, "/".join(parts), body))
        coll = self.db[parts[0]]
        if len(parts) == 1 and method == "GET":
            rows = [r for r in coll if "child" not in q or str(r.get("child")) == q["child"]]
            if "start_min" in q:
                lo = datetime.fromisoformat(q["start_min"])
                rows = [r for r in rows if datetime.fromisoformat(r["start"]) >= lo]
            return {"results": [dict(r) for r in rows], "next": None}
        if len(parts) == 1 and method == "POST":
            return self.add(parts[0], **body)
        row = next(r for r in coll if r["id"] == int(parts[1]))
        if method == "PATCH":
            row.update(body)
            return dict(row)
        if method == "DELETE":
            coll.remove(row)
            return None
        raise AssertionError(f"uventet kald {method} {url}")
