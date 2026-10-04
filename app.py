"""Napper webapp: start/stop søvn + forudsigelse. Bruger napper.py som motor."""
import math, struct, threading, time, zlib
from datetime import datetime, timedelta, date
from flask import Flask, Response, jsonify, request, send_from_directory
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


def last_sleep_end(cid, now):
    since = (now - timedelta(days=3)).isoformat().replace("+", "%2B")
    raw = napper.bb_all(f"sleep/?child={cid}&start_min={since}&limit=200")
    return max((napper.parse(x["end"]) for x in raw if x.get("end")), default=None)


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
    try:
        fsince = (now - timedelta(days=2)).isoformat().replace("+", "%2B")
        fs = napper.bb_all(f"feedings/?child={c['id']}&start_min={fsince}&limit=100")
        lf = max(fs, key=lambda f: napper.parse(f["start"]), default=None)
        last_feed = lf and {"time": napper.parse(lf["start"]).isoformat(), "method": lf["method"],
                            "type": lf["type"], "amount": lf.get("amount")}
    except Exception:
        last_feed = None
    return jsonify(
        sleeping=bool(t),
        since=start.isoformat() if start else None,
        nap_guess=nap_guess(start or now),
        awake_since=max((s["end"] for s in sleeps), default=None) and max(s["end"] for s in sleeps).isoformat(),
        prediction=pred,
        last_feed=last_feed,
        today=[{"id": s["id"], "start": s["start"].isoformat(), "end": s["end"].isoformat(), "nap": s["nap"]}
               for s in sorted(sleeps, key=lambda s: s["start"])
               if now.date() in (s["start"].date(), s["end"].date())],
    )


@app.post("/api/start")
def start():
    c = get_child()
    if sleep_timer(c["id"]):
        return jsonify(ok=True)
    now = datetime.now(TZ)
    st, since = now, (request.get_json(silent=True) or {}).get("since")
    if since:  # "HH:MM" = faldt i søvn kl.
        try:
            h, m = map(int, str(since).split(":")[:2])
            st = now.replace(hour=h, minute=m, second=0, microsecond=0)
        except ValueError:
            return jsonify(ok=False, error="Ugyldigt tidspunkt"), 400
        if st > now:
            st -= timedelta(days=1)
        last = last_sleep_end(c["id"], now)
        if last and st < last:
            return jsonify(ok=False, error=f"Forrige søvn sluttede kl. {last:%H:%M}"), 400
    bb("timers/", "POST", {"child": c["id"], "name": TIMER, "start": st.isoformat()})
    return jsonify(ok=True)


@app.post("/api/stop")
def stop():
    c = get_child()
    t = sleep_timer(c["id"])
    if not t:
        return jsonify(ok=False, error="Ingen søvn i gang"), 409
    now = datetime.now(TZ)
    body = request.get_json(silent=True) or {}
    s, e = napper.parse(t["start"]), now
    if body.get("wake"):  # "HH:MM" = vågnede kl.
        try:
            h, m = map(int, str(body["wake"]).split(":")[:2])
            e = now.replace(hour=h, minute=m, second=0, microsecond=0)
        except ValueError:
            return jsonify(ok=False, error="Ugyldigt tidspunkt"), 400
        if e > now:  # fx 23:50 tastet lige efter midnat
            e -= timedelta(days=1)
        if e <= s:
            return jsonify(ok=False, error=f"Søvnen startede kl. {s:%H:%M}"), 400
    nap = body.get("nap", nap_guess(s))
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


def local(txt):  # "YYYY-MM-DDTHH:MM" (lokal tid) -> tidszonebevidst datetime
    return datetime.fromisoformat(txt).replace(tzinfo=TZ)


@app.post("/api/sleep/<int:sid>")
def edit_sleep(sid):
    """Ret start/slut (og lur/nat) på en gemt søvn."""
    d = request.get_json(silent=True) or {}
    try:
        s, e = local(d["start"]), local(d["end"])
    except (KeyError, ValueError):
        return jsonify(ok=False, error="Ugyldigt tidspunkt"), 400
    if e <= s:
        return jsonify(ok=False, error="Sluttid skal være efter starttid"), 400
    if e > datetime.now(TZ) + timedelta(minutes=1):
        return jsonify(ok=False, error="Sluttid ligger i fremtiden"), 400
    body = {"start": s.isoformat(), "end": e.isoformat()}
    if "nap" in d:
        body["nap"] = bool(d["nap"])
    bb(f"sleep/{sid}/", "PATCH", body)
    return jsonify(ok=True)


@app.delete("/api/sleep/<int:sid>")
def delete_sleep(sid):
    bb(f"sleep/{sid}/", "DELETE")
    return jsonify(ok=True)


BREAST = {"left": "left breast", "right": "right breast", "both": "both breasts"}


@app.post("/api/feed")
def feed():
    """Log et måltid: kind = left|right|both|bottle (bottle kræver amount i ml)."""
    d = request.get_json(silent=True) or {}
    now = datetime.now(TZ)
    try:
        t = now
        if d.get("at"):  # "HH:MM", i går hvis tiden ligger i fremtiden
            h, m = map(int, str(d["at"]).split(":")[:2])
            t = now.replace(hour=h, minute=m, second=0, microsecond=0)
            if t > now:
                t -= timedelta(days=1)
        body = {"child": get_child()["id"], "start": t.isoformat(), "end": t.isoformat()}
        if d.get("kind") == "bottle":
            amount = float(d["amount"])
            if not 0 < amount <= 500:
                raise ValueError
            body.update(type="formula" if d.get("milk") == "formula" else "breast milk",
                        method="bottle", amount=amount)
        elif d.get("kind") in BREAST:
            body.update(type="breast milk", method=BREAST[d["kind"]])
        else:
            raise ValueError
    except (KeyError, ValueError):
        return jsonify(ok=False, error="Ugyldigt måltid"), 400
    bb("feedings/", "POST", body)
    return jsonify(ok=True)


def make_icon(n=512):
    """Hjemmeskærm-ikon (PNG) tegnet uden eksterne biblioteker: måne og stjerner på natblå."""
    def mix(a, b, t):
        return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))

    def shade(x, y):
        c = mix((34, 52, 107), (10, 16, 34), y)
        g = max(0.0, 1 - math.hypot(x - .5, y - .5) / .55)
        c = mix(c, (110, 160, 255), .30 * g * g)
        if math.hypot(x - .47, y - .52) < .27 and math.hypot(x - .58, y - .43) >= .23:
            return mix((243, 246, 255), (157, 182, 255), (x + y) / 2)
        for sx, sy, r in ((.68, .36, .07), (.80, .56, .04), (.30, .24, .035)):
            if (abs(x - sx) / r) ** .5 + (abs(y - sy) / r) ** .5 < 1:
                return (255, 226, 138)
        return c

    rows = bytearray()
    for j in range(n):
        rows.append(0)
        for i in range(n):
            acc = [0, 0, 0]
            for dx in (.25, .75):
                for dy in (.25, .75):
                    p = shade((i + dx) / n, (j + dy) / n)
                    for k in range(3):
                        acc[k] += p[k]
            rows += bytes(int(v / 4) for v in acc)

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b""))


_icon = []


@app.get("/icon.png")
@app.get("/apple-touch-icon.png")
def icon():
    if not _icon:
        _icon.append(make_icon())
    return Response(_icon[0], mimetype="image/png", headers={"Cache-Control": "public, max-age=86400"})


@app.get("/manifest.json")
def manifest():
    return jsonify(name="Folke-App", short_name="Folke-App", start_url="/", display="standalone",
                   background_color="#0a1022", theme_color="#0a1022",
                   icons=[{"src": "/icon.png", "sizes": "512x512", "type": "image/png"}])


@app.get("/")
def index():
    return send_from_directory(".", "index.html")


@app.errorhandler(Exception)
def err(e):
    msg = str(e)
    if hasattr(e, "read"):  # HTTP-fejl fra Baby Buddy: vis begrundelsen
        try:
            msg += " " + e.read().decode()[:200]
        except Exception:
            pass
    return jsonify(ok=False, error=msg), 502


def loop():
    """Opdaterer HA-sensor og sender notifikationer (samme logik som napper.py)."""
    while True:
        try:
            napper.main()
        except Exception as e:
            print("loop:", e, flush=True)
        time.sleep(60)


threading.Thread(target=loop, daemon=True).start()
