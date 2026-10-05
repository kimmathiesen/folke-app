"""Tavlen: fælles tegning for begge forældre (tegn, fortryd, visk ud, versioner, grænser)."""
import pytest

import app as app_module

HEART = {"c": "#ff8fa3", "w": 0.012, "p": [[0.5, 0.3], [0.3, 0.2], [0.2, 0.4], [0.5, 0.7], [0.8, 0.4], [0.7, 0.2], [0.5, 0.3]]}


@pytest.fixture
def board(monkeypatch, tmp_path):
    monkeypatch.setattr(app_module, "BOARD", str(tmp_path / "board.json"))
    return app_module.app.test_client()


def test_tom_tavle(board):
    assert board.get("/api/board").get_json() == {"version": 0, "strokes": [], "by": None, "updated": None}


def test_tegn_og_se_det_paa_den_anden_enhed(board):
    r = board.post("/api/board/stroke", json={"stroke": HEART, "by": "far"}).get_json()
    assert r["version"] == 1 and r["by"] == "far" and r["strokes"] == [HEART]
    other = board.get("/api/board").get_json()  # mors telefon
    assert other["strokes"] == [HEART] and other["updated"]
    assert board.get("/api/board?v=1").get_json() == {"version": 1, "same": True}  # intet nyt


def test_fortryd_og_visk_ud_gaelder_for_begge(board):
    board.post("/api/board/stroke", json={"stroke": HEART, "by": "far"})
    board.post("/api/board/stroke", json={"stroke": {**HEART, "c": "#ffd27a"}, "by": "mor"})
    r = board.post("/api/board/undo", json={"by": "mor"}).get_json()
    assert [s["c"] for s in r["strokes"]] == ["#ff8fa3"] and r["version"] == 3
    r = board.post("/api/board/clear", json={"by": "mor"}).get_json()
    assert r["strokes"] == [] and r["version"] == 4 and r["by"] == "mor"
    assert board.get("/api/board").get_json()["strokes"] == []
    assert board.post("/api/board/undo", json={}).get_json()["version"] == 4  # tom tavle: intet ændres


@pytest.mark.parametrize("stroke", [
    None, {**HEART, "c": "red"}, {**HEART, "w": 1}, {**HEART, "p": []}, {**HEART, "p": [[1.5, 0.2]]},
    {**HEART, "p": [["x", 0]]}, {**HEART, "p": [[0.1, 0.1]] * 2001},
])
def test_ugyldige_streger(board, stroke):
    assert board.post("/api/board/stroke", json={"stroke": stroke}).status_code == 400
    assert board.get("/api/board").get_json()["version"] == 0


def test_fuld_tavle(board, monkeypatch):
    monkeypatch.setattr(app_module, "MAX_TOTAL", 10)
    assert board.post("/api/board/stroke", json={"stroke": HEART}).status_code == 200
    r = board.post("/api/board/stroke", json={"stroke": HEART})
    assert r.status_code == 400 and "fuld" in r.get_json()["error"]


def test_ukendt_afsender_gemmes_ikke(board):
    assert board.post("/api/board/stroke", json={"stroke": HEART, "by": "<script>"}).get_json()["by"] is None


def test_status_viser_tavlens_version(client, board):
    board.post("/api/board/stroke", json={"stroke": HEART})
    assert client.get("/api/status").get_json()["board"] == 1
