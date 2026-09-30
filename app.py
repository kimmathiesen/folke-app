"""Napper webapp: start/stop søvn + forudsigelse. Bruger napper.py som motor."""
import threading, time
from datetime import datetime, timedelta, date
from flask import Flask, jsonify, request, send_from_directory
import napper

app = Flask(__name__)
TZ, TIMER = napper.TZ, "Søvn"


def bb(path, method="GET", body=None):
    return napper.call(f"{napper.BB_URL}/api/{path}", napper.BB_TOKEN, method, body)


def get_child():
    cs = napper.bb_all("children/")
    return next((c for c in cs if not napper.CHILD_ID or str(c["id"]) == napper.CHILD_ID), None)


def nap_guess(start):
    return not (start.hour >= 18 or start.hour < 5)


def sleep_timer(cid):
    return next((t for t in napper.bb_all(f"timers/?child={cid}") if t["name"] == TIMER), None)


@app.get("/api/status")
def status():
    now = datetime.now(TZ)
    c = get_child()
    t = sleep_timer(c["id"])
    since = (now - timedelta(days=napper.HISTORY_DAYS)).isoformat()
    raw = napper.bb_all(f"sleep/?child={c['id']}&start_min={since.replace('+', '%2B')}&limit=200")
    sleeps = [{"id": s["id"], "start": napper.parse(s["start"]), "end": napper.parse(s["end"]),
               "nap": s["nap"]} for s in raw if s.get("end")]
    pred = None if t else napper.predict(sleeps, date.fromisoformat(c["birth_date"]), now)
    if pred:
        pred["time"] = pred["time"].isoformat()
    start = napper.parse(t["start"]) if t else None
    return jsonify(
        sleeping=bool(t),
        since=start.isoformat() if start else None,
        nap_guess=nap_guess(start or now),
        awake_since=max((s["end"] for s in sleeps), default=None) and max(s["end"] for s in sleeps).isoformat(),
        prediction=pred,
        today=[{"start": s["start"].isoformat(), "end": s["end"].isoformat(), "nap": s["nap"]}
               for s in sorted(sleeps, key=lambda s: s["start"]) if s["start"].date() == now.date()],
    )


@app.post("/api/start")
def start():
    c = get_child()
    if not sleep_timer(c["id"]):
        bb("timers/", "POST", {"child": c["id"], "name": TIMER, "start": datetime.now(TZ).isoformat()})
    return jsonify(ok=True)


@app.post("/api/stop")
def stop():
    c = get_child()
    t = sleep_timer(c["id"])
    if not t:
        return jsonify(ok=False, error="Ingen søvn i gang"), 409
    s, e = napper.parse(t["start"]), datetime.now(TZ)
    nap = (request.get_json(silent=True) or {}).get("nap", nap_guess(s))
    bb("sleep/", "POST", {"child": c["id"], "start": s.isoformat(), "end": e.isoformat(), "nap": nap})
    bb(f"timers/{t['id']}/", "DELETE")
    return jsonify(ok=True)


@app.post("/api/pump")
def pump():
    """Log en pumpning (ml). Kaldes fra Home Assistant via rest_command."""
    data = request.get_json(silent=True) or {}
    try:
        amount = float(data.get("amount", 0))
    except (TypeError, ValueError):
        amount = 0
    if not 0 < amount <= 1000:
        return jsonify(ok=False, error="Ugyldig mængde"), 400
    now = datetime.now(TZ).isoformat()
    bb("pumping/", "POST", {"child": get_child()["id"], "amount": amount,
                            "start": now, "end": now, "notes": data.get("notes", "")})
    return jsonify(ok=True, amount=amount)


@app.get("/manifest.json")
def manifest():
    return jsonify(name="Napper", short_name="Napper", start_url="/", display="standalone",
                   background_color="#111418", theme_color="#111418")


@app.get("/")
def index():
    return send_from_directory(".", "index.html")


@app.errorhandler(Exception)
def err(e):
    return jsonify(ok=False, error=str(e)), 502


def loop():
    """Opdaterer HA-sensor og sender notifikationer (samme logik som napper.py)."""
    while True:
        try:
            napper.main()
        except Exception as e:
            print("loop:", e, flush=True)
        time.sleep(60)


threading.Thread(target=loop, daemon=True).start()
