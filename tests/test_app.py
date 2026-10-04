"""API'erne i app.py mod en falsk Baby Buddy (napper.call erstattes, intet netværk)."""
import urllib.parse
from datetime import date, datetime, timedelta

import pytest

import napper
import app as app_module

TZ = napper.TZ


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


def now():
    return datetime.now(TZ)


def hm(t):
    return f"{t:%H:%M}"


@pytest.fixture
def bb(monkeypatch, tmp_path):
    fake = FakeBB(birth=now().date() - timedelta(days=120))
    monkeypatch.setattr(napper, "call", fake)
    monkeypatch.setattr(app_module, "PREFS", str(tmp_path / "prefs.json"))
    monkeypatch.setattr(app_module, "GROWTH", str(tmp_path / "growth.json"))
    app_module._sc.update(t=0, v=[])
    return fake


@pytest.fixture
def client(bb):
    return app_module.app.test_client()


def add_sleep(bb, start, end, nap=True):
    return bb.add("sleep", start=start.isoformat(), end=end.isoformat(), nap=nap)


# ---------- status ----------
def test_status_uden_data(client):
    d = client.get("/api/status").get_json()
    assert d["sleeping"] is False
    assert d["prediction"] is None
    assert d["today"] == []
    assert d["features"] == {"breast": True, "solids": False}
    assert d["suggestions"] == []


def test_status_med_soevn_giver_forudsigelse(client, bb):
    t = now()
    add_sleep(bb, t - timedelta(days=1, hours=3), t - timedelta(days=1, hours=2))
    s = add_sleep(bb, t - timedelta(minutes=30), t)
    d = client.get("/api/status").get_json()
    assert d["prediction"]["last_id"] == s["id"]
    assert d["prediction"]["source"] == "aldersbaseret standard"
    assert d["awake_since"] == napper.parse(s["end"]).isoformat()
    assert s["id"] in [x["id"] for x in d["today"]]


# ---------- start/stop ----------
def test_start_opretter_timer_og_er_idempotent(client, bb):
    assert client.post("/api/start").get_json() == {"ok": True}
    assert client.post("/api/start").status_code == 200
    assert len(bb.db["timers"]) == 1
    assert bb.db["timers"][0]["name"] == "Søvn"
    d = client.get("/api/status").get_json()
    assert d["sleeping"] is True and d["prediction"] is None


def test_start_med_tidspunkt(client, bb):
    since = now() - timedelta(minutes=20)
    assert client.post("/api/start", json={"since": hm(since)}).status_code == 200
    assert hm(napper.parse(bb.db["timers"][0]["start"])) == hm(since)


def test_start_ugyldigt_tidspunkt(client, bb):
    assert client.post("/api/start", json={"since": "xx"}).status_code == 400
    assert bb.db["timers"] == []


def test_start_foer_forrige_soevn_afvises(client, bb):
    t = now()
    add_sleep(bb, t - timedelta(hours=2), t - timedelta(minutes=30))
    r = client.post("/api/start", json={"since": hm(t - timedelta(hours=1))})
    assert r.status_code == 400
    assert "Forrige søvn" in r.get_json()["error"]


def test_stop_uden_timer(client):
    assert client.post("/api/stop").status_code == 409


def test_stop_gemmer_soevn_og_sletter_timer(client, bb):
    st = (now() - timedelta(hours=1)).replace(microsecond=0)
    bb.add("timers", name="Søvn", start=st.isoformat())
    assert client.post("/api/stop", json={"nap": True}).status_code == 200
    assert bb.db["timers"] == []
    [s] = bb.db["sleep"]
    assert napper.parse(s["start"]) == st and s["nap"] is True
    assert ("DELETE", f"timers/{100}", None) in bb.calls


def test_stop_med_vaagnetidspunkt(client, bb):
    bb.add("timers", name="Søvn", start=(now() - timedelta(hours=2)).isoformat())
    wake = now() - timedelta(minutes=30)
    assert client.post("/api/stop", json={"wake": hm(wake), "nap": False}).status_code == 200
    assert hm(napper.parse(bb.db["sleep"][0]["end"])) == hm(wake)


def test_stop_vaagnet_foer_start_afvises(client, bb):
    bb.add("timers", name="Søvn", start=(now() - timedelta(hours=1)).isoformat())
    r = client.post("/api/stop", json={"wake": hm(now() - timedelta(hours=2))})
    assert r.status_code == 400
    assert len(bb.db["timers"]) == 1 and bb.db["sleep"] == []


# ---------- ret/slet søvn ----------
def test_ret_og_slet_soevn(client, bb):
    s = add_sleep(bb, now() - timedelta(hours=5), now() - timedelta(hours=4))
    y = (now() - timedelta(days=1)).date()
    r = client.post(f"/api/sleep/{s['id']}", json={"start": f"{y}T13:00", "end": f"{y}T14:15", "nap": False})
    assert r.status_code == 200
    assert bb.db["sleep"][0]["end"] == datetime.fromisoformat(f"{y}T14:15").replace(tzinfo=TZ).isoformat()
    assert bb.db["sleep"][0]["nap"] is False
    assert client.delete(f"/api/sleep/{s['id']}").status_code == 200
    assert bb.db["sleep"] == []


def test_ret_soevn_slut_foer_start(client, bb):
    s = add_sleep(bb, now() - timedelta(hours=5), now() - timedelta(hours=4))
    y = (now() - timedelta(days=1)).date()
    r = client.post(f"/api/sleep/{s['id']}", json={"start": f"{y}T14:00", "end": f"{y}T13:00"})
    assert r.status_code == 400


# ---------- mad og pumpning ----------
@pytest.mark.parametrize("amount", [0, -5, 2000, "abc", None])
def test_pump_ugyldig(client, bb, amount):
    assert client.post("/api/pump", json={"amount": amount}).status_code == 400
    assert bb.db["pumping"] == []


def test_pump(client, bb):
    assert client.post("/api/pump", json={"amount": 120}).get_json() == {"ok": True, "amount": 120.0}
    assert bb.db["pumping"][0]["amount"] == 120.0 and bb.db["pumping"][0]["child"] == 1


@pytest.mark.parametrize("body,expect", [
    ({"kind": "left"}, {"type": "breast milk", "method": "left breast"}),
    ({"kind": "both"}, {"type": "breast milk", "method": "both breasts"}),
    ({"kind": "bottle", "amount": 90}, {"type": "breast milk", "method": "bottle", "amount": 90.0}),
    ({"kind": "bottle", "amount": 90, "milk": "formula"}, {"type": "formula", "method": "bottle"}),
    ({"kind": "solid", "note": "gulerod"}, {"type": "solid food", "notes": "gulerod"}),
])
def test_feed(client, bb, body, expect):
    assert client.post("/api/feed", json=body).status_code == 200
    f = bb.db["feedings"][0]
    assert expect.items() <= f.items()


@pytest.mark.parametrize("body", [{"kind": "x"}, {"kind": "bottle"}, {"kind": "bottle", "amount": 600},
                                  {"kind": "left", "at": "aa:bb"}])
def test_feed_ugyldig(client, bb, body):
    assert client.post("/api/feed", json=body).status_code == 400
    assert bb.db["feedings"] == []


def test_feed_med_tidspunkt(client, bb):
    t = now() - timedelta(minutes=45)
    client.post("/api/feed", json={"kind": "right", "at": hm(t)})
    assert hm(napper.parse(bb.db["feedings"][0]["start"])) == hm(t)


# ---------- vækst ----------
def test_vaekst_gem_og_hent(client, bb):
    birth = date.fromisoformat(bb.db["children"][0]["birth_date"])
    day = (birth + timedelta(days=91)).isoformat()
    assert client.post("/api/growth", json={"date": day, "w": "6,4", "l": 61.4}).status_code == 200
    d = client.get("/api/growth").get_json()
    [e] = d["entries"]
    assert e["w"] == 6.4 and e["h"] is None
    assert 40 <= e["pw"] <= 60 and e["ph"] is None
    assert set(d["curves"]) == {"w", "l", "h"}
    assert client.post(f"/api/growth/{e['id']}", json={"date": day, "w": 6.5}).status_code == 200
    assert client.get("/api/growth").get_json()["entries"][0]["w"] == 6.5
    assert client.delete(f"/api/growth/{e['id']}").status_code == 200
    assert client.get("/api/growth").get_json()["entries"] == []


@pytest.mark.parametrize("body", [
    {"date": "i går", "w": 5},
    {"date": (date.today() + timedelta(days=2)).isoformat(), "w": 5},
    {"date": "2026-01-01", "w": 50},
    {"date": "2026-01-01"},
])
def test_vaekst_ugyldig(client, body):
    assert client.post("/api/growth", json=body).status_code == 400


# ---------- forslag og tilpasning ----------
def test_forslag_fast_foede_ved_6_mdr(client, bb):
    bb.db["children"][0]["birth_date"] = (now().date() - timedelta(days=200)).isoformat()
    sug = client.get("/api/status").get_json()["suggestions"]
    assert [s["id"] for s in sug] == ["solids"]
    assert client.post("/api/suggestion", json={"id": "solids", "answer": "yes"}).status_code == 200
    d = client.get("/api/status").get_json()
    assert d["features"]["solids"] is True and d["suggestions"] == []


def test_forslag_skjul_amning(client, bb):
    bb.add("feedings", start=(now() - timedelta(days=30)).isoformat(), method="left breast", type="breast milk")
    assert [s["id"] for s in client.get("/api/status").get_json()["suggestions"]] == ["hide_breast"]
    client.post("/api/suggestion", json={"id": "hide_breast", "answer": "later"})
    assert client.get("/api/status").get_json()["suggestions"] == []
    assert client.get("/api/status").get_json()["features"]["breast"] is True


def test_forslag_ugyldigt_svar(client):
    assert client.post("/api/suggestion", json={"id": "solids", "answer": "måske"}).status_code == 400


def test_feature_og_profil(client):
    assert client.post("/api/feature", json={"name": "solids", "on": True}).status_code == 200
    assert client.post("/api/feature", json={"name": "x"}).status_code == 400
    assert client.post("/api/profile", json={"sex": "girl"}).status_code == 200
    assert client.post("/api/profile", json={"sex": "x"}).status_code == 400
    d = client.get("/api/status").get_json()
    assert d["features"]["solids"] is True and d["sex"] == "girl"


def test_baby_buddy_fejl_giver_502(client, monkeypatch):
    def boom(*a, **k):
        raise OSError("forbindelse nægtet")
    monkeypatch.setattr(napper, "call", boom)
    r = client.get("/api/status")
    assert r.status_code == 502 and "forbindelse" in r.get_json()["error"]
