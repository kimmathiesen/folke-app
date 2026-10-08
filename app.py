"""Folke webapp: start/stop søvn + forudsigelse. Bruger folke.py som motor."""
import json, math, os, struct, threading, time, zlib
from datetime import datetime, timedelta, date
from flask import Flask, Response, jsonify, request, send_from_directory
from werkzeug.exceptions import HTTPException
import evaluate, folke, push, store, who

app = Flask(__name__)
TZ = folke.TZ
folke.push = push


def db():
    return store.get()


def get_child():
    c = db().child()
    if not c:
        raise LookupError("Intet barn. Opret barnet ved første opstart eller sæt CHILD_BIRTH")
    return c


def nap_guess(start):
    return not (start.hour >= 18 or start.hour < 5)


def sleep_timer(cid):
    return db().timer(cid)


def last_sleep_end(cid, now):
    raw = db().sleeps(cid, now - timedelta(days=3))
    return max((folke.parse(x["end"]) for x in raw), default=None)


@app.get("/api/status")
def status():
    now = datetime.now(TZ)
    c = db().child()
    if not c:  # første opstart uden import: UI'et spørger om navn og fødselsdato
        return jsonify(setup=True)
    t = sleep_timer(c["id"])
    raw = db().sleeps(c["id"], now - timedelta(days=folke.HISTORY_DAYS))
    wakes = db().wakes(c["id"], now - timedelta(days=2))
    sleeps = [{"id": s["id"], "start": folke.parse(s["start"]), "end": folke.parse(s["end"]),
               "nap": s["nap"]} for s in raw]
    birth = date.fromisoformat(c["birth_date"])
    pred = None if t else folke.predict(sleeps, birth, now)
    if pred:
        pred["time"] = pred["time"].isoformat()
    start = folke.parse(t["start"]) if t else None
    # Dagsplan: også mens en lur er i gang (regnet fra forventet opvågning), ikke om natten
    plan = None if t and not nap_guess(start) else folke.plan_day(sleeps, birth, now, running=start)
    if plan:
        iso_ = lambda v: v.isoformat() if isinstance(v, datetime) else v  # noqa: E731
        plan = {k: iso_(v) for k, v in plan.items() if k != "items"} | {
            "items": [{k: iso_(v) for k, v in x.items()} for x in plan["items"]]}
    try:
        fs = db().feedings(c["id"], now - timedelta(days=2))
        lf = max(fs, key=lambda f: folke.parse(f["start"]), default=None)
        last_feed = lf and {"time": folke.parse(lf["start"]).isoformat(), "method": lf["method"],
                            "type": lf["type"], "amount": lf.get("amount")}
        # Dagens måltider til Mad-siden, nyeste først
        feed_today = [{"time": folke.parse(f["start"]).isoformat(), "method": f["method"], "type": f["type"],
                       "amount": f.get("amount"), "notes": f.get("notes")}
                      for f in sorted(fs, key=lambda f: folke.parse(f["start"]), reverse=True)
                      if folke.parse(f["start"]).astimezone(TZ).date() == now.date()]
    except Exception:
        last_feed, feed_today = None, []
    return jsonify(
        sleeping=bool(t),
        since=start.isoformat() if start else None,
        nap_guess=nap_guess(start or now),
        awake_since=max((s["end"] for s in sleeps), default=None) and max(s["end"] for s in sleeps).isoformat(),
        prediction=pred,
        plan=plan,
        last_feed=last_feed,
        accuracy=accuracy(c, now),
        feed_today=feed_today,
        pump=pump_summary(c["id"], now),
        pump_remind=prefs()["pump_remind"],
        can_notify=folke.can_notify(),
        child_name=child_name(c),
        birth_date=c["birth_date"],
        push_devices=len(push.load()),
        notify_lead=folke.LEAD_MIN,
        notify_overdue=folke.OVERDUE_MIN,
        board=(lambda b: b["version"] if b["strokes"] else 0)(load_board()),
        features=prefs()["features"],
        sex=prefs()["sex"],
        suggestions=current_suggestions(c, now, prefs()),
        today=[{"id": s["id"], "start": s["start"].isoformat(), "end": s["end"].isoformat(), "nap": s["nap"],
                "wakes": [] if s["nap"] else wakes_in(wakes, s["start"], s["end"])}
               for s in sorted(sleeps, key=lambda s: s["start"])
               if now.date() in (s["start"].date(), s["end"].date())],
        night_wakes=wakes_in(wakes, start, None) if start else [],
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
    db().start_timer(c["id"], st)
    return jsonify(ok=True)


@app.post("/api/stop")
def stop():
    c = get_child()
    t = sleep_timer(c["id"])
    if not t:
        return jsonify(ok=False, error="Ingen søvn i gang"), 409
    now = datetime.now(TZ)
    body = request.get_json(silent=True) or {}
    s, e = folke.parse(t["start"]), now
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
    # Har brugeren ikke selv valgt lur/nat, gættes der ud fra både start og længde (aftenlur efter kl. 18 = lur)
    w = db().open_wake(c["id"])
    if w:  # vågen om natten og ikke faldet i søvn igen: natten sluttede, da han vågnede
        db().delete_wake(w["id"])
        if not body.get("wake"):
            e = max(folke.parse(w["start"]), s + timedelta(minutes=1))
    nap = body["nap"] if "nap" in body else folke.nap_at_stop(s, e)
    db().add_sleep(c["id"], s, e, nap)
    db().delete_timer(t["id"])
    return jsonify(ok=True)


@app.post("/api/wake")
def night_wake():
    """Opvågning om natten, mens natten kører: {"action": "start"} (vågnede) eller {"action": "stop"} (sover igen)."""
    c = get_child()
    t = sleep_timer(c["id"])
    if not t:
        return jsonify(ok=False, error="Ingen søvn i gang"), 409
    now = datetime.now(TZ)
    w = db().open_wake(c["id"])
    action = (request.get_json(silent=True) or {}).get("action")
    if action == "start":
        if not w:
            db().add_wake(c["id"], now)
    elif action == "stop":
        if w:
            db().end_wake(w["id"], now)
    else:
        return jsonify(ok=False, error="Ugyldig handling"), 400
    return jsonify(ok=True)


@app.delete("/api/wake/<int:wid>")
def delete_night_wake(wid):
    db().delete_wake(wid)
    return jsonify(ok=True)


def wakes_in(wakes, start, end):
    """Opvågninger, der startede i søvnen [start, end] (end None = søvnen kører)."""
    return [{"id": w["id"], "start": folke.parse(w["start"]).isoformat(),
             "end": w["end"] and folke.parse(w["end"]).isoformat()}
            for w in wakes if start <= folke.parse(w["start"]) and (end is None or folke.parse(w["start"]) <= end)]


# ---------- Udpumpning ----------
SIDES = ("left", "right", "both")


def clock(txt, now):
    """"HH:MM" -> i dag, eller i går hvis tiden ligger i fremtiden."""
    h, m = map(int, str(txt).split(":")[:2])
    t = now.replace(hour=h, minute=m, second=0, microsecond=0)
    return t - timedelta(days=1) if t > now else t


def clean_pump(d):
    """Mængde (påkrævet), side og minutter (valgfri) fra en forespørgsel."""
    try:
        amount = float(str(d.get("amount", 0)).replace(",", "."))
    except (TypeError, ValueError):
        amount = 0
    if not 0 < amount <= 1000:
        raise ValueError("Ugyldig mængde")
    side = d.get("side") or None
    if side not in (None, *SIDES):
        raise ValueError("Ugyldig side")
    minutes = d.get("minutes")
    if minutes in (None, ""):
        minutes = None
    else:
        try:
            minutes = float(str(minutes).replace(",", "."))
        except ValueError:
            raise ValueError("Ugyldigt antal minutter")
        if not 0 < minutes <= 180:
            raise ValueError("Minutter skal være mellem 1 og 180")
    return {"amount": amount, "side": side, "minutes": minutes}


@app.post("/api/pump")
def pump():
    """Log en udpumpning fra appen: {"amount": ml}.
    Valgfrit: "at": "HH:MM", "side": left|right|both, "minutes", "notes"."""
    data = request.get_json(silent=True) or {}
    now = datetime.now(TZ)
    try:
        p = clean_pump(data)
    except ValueError as e:
        return jsonify(ok=False, error=str(e)), 400
    try:
        t = clock(data["at"], now) if data.get("at") else now
    except ValueError:
        return jsonify(ok=False, error="Ugyldigt tidspunkt"), 400
    db().add_pumping(get_child()["id"], start=t, end=t, notes=data.get("notes", ""), **p)
    return jsonify(ok=True, amount=p["amount"])


@app.post("/api/pump/<int:pid>")
def edit_pump(pid):
    d = request.get_json(silent=True) or {}
    try:
        t = local(d["start"])
    except (KeyError, ValueError):
        return jsonify(ok=False, error="Ugyldigt tidspunkt"), 400
    try:
        p = clean_pump(d)
    except ValueError as e:
        return jsonify(ok=False, error=str(e)), 400
    if t > datetime.now(TZ) + timedelta(minutes=1):
        return jsonify(ok=False, error="Tidspunktet ligger i fremtiden"), 400
    db().edit_pumping(pid, t, **p)
    return jsonify(ok=True)


@app.delete("/api/pump/<int:pid>")
def delete_pump(pid):
    db().delete_pumping(pid)
    return jsonify(ok=True)


def pump_rows(cid, since):
    return [{"id": r["id"], "start": folke.parse(r["start"]).isoformat(), "amount": r.get("amount"),
             "side": r.get("side"), "minutes": r.get("minutes")}
            for r in sorted(db().pumpings(cid, since), key=lambda r: r["start"])]


def pump_summary(cid, now):
    rows = pump_rows(cid, now - timedelta(days=2))
    today = [r for r in rows if datetime.fromisoformat(r["start"]).date() == now.date()]
    return {"today_ml": round(sum(r["amount"] or 0 for r in today)), "today_count": len(today),
            "last": rows[-1] if rows else None}


@app.get("/api/pump/history")
def pump_history():
    """Ml og antal pr. dag (lokal dato) de seneste `days` dage, plus de enkelte udpumpninger."""
    days = min(max(request.args.get("days", 14, type=int), 1), 90)
    now = datetime.now(TZ)
    first = now.date() - timedelta(days=days - 1)
    start = datetime(first.year, first.month, first.day, tzinfo=TZ)
    rows = pump_rows(get_child()["id"], start)
    per = {first + timedelta(days=i): {"ml": 0, "count": 0} for i in range(days)}
    for r in rows:
        d = per.get(datetime.fromisoformat(r["start"]).date())
        if d is not None:
            d["ml"] += r["amount"] or 0
            d["count"] += 1
    out = [{"date": d.isoformat(), "ml": round(v["ml"]), "count": v["count"]} for d, v in sorted(per.items())]
    full = [x["ml"] for x in out[:-1] if x["count"]]  # i dag er ikke færdig
    return jsonify(days=out, avg_ml=round(sum(full) / len(full)) if full else None,
                   items=list(reversed(rows)), remind=prefs()["pump_remind"])


@app.post("/api/pump/remind")
def pump_remind():
    d = request.get_json(silent=True) or {}
    try:
        h = float(d.get("hours", 0))
    except (TypeError, ValueError):
        h = -1
    if not 0 <= h <= 12:
        return jsonify(ok=False, error="Vælg 0-12 timer"), 400
    p = prefs()
    p["pump_remind"] = h
    save_prefs(p)
    return jsonify(ok=True)


QUIET = (22, 7)  # ingen påmindelser om udpumpning mellem 22 og 7


def pump_reminder(now):
    """Notifikation (web push), når der er gået `pump_remind` timer siden sidste udpumpning.
    Én gang pr. udpumpning, og ikke om natten."""
    p = prefs()
    h = p["pump_remind"]
    if not (h and p["features"]["pump"] and folke.can_notify("pump")):
        return False
    if now.hour >= QUIET[0] or now.hour < QUIET[1]:
        return False
    c = db().child()
    last = c and pump_summary(c["id"], now)["last"]
    if not last:
        return False
    t = datetime.fromisoformat(last["start"])
    if now - t < timedelta(hours=h):
        return False
    state = folke.load_state()
    if state.get("pump_notified") == last["id"]:
        return False
    hrs = (now - t).total_seconds() / 3600
    folke.notify("Udpumpning", f"Det er {hrs:.0f} timer siden sidste udpumpning (kl. {t:%H:%M})", kind="pump")
    state["pump_notified"] = last["id"]
    folke.save_state(state)
    return True


PREFS = os.path.join(os.path.dirname(folke.STATE_FILE) or ".", "prefs.json")
_sc = {"t": 0, "v": []}
_acc = {"t": 0, "v": None}


def accuracy(c, now):
    """Hvor godt forudsigelsen har ramt de seneste 14 dage (evaluate.backtest) og intervallet ud fra det.
    Beregnes højst hvert 10. minut."""
    if time.time() - _acc["t"] > 600:
        try:
            raw = db().sleeps(c["id"], now - timedelta(days=14 + folke.HISTORY_DAYS))
            sleeps = [{"id": s["id"], "start": folke.parse(s["start"]), "end": folke.parse(s["end"]), "nap": s["nap"]}
                      for s in raw]
            res = [r for r in evaluate.backtest(sleeps, date.fromisoformat(c["birth_date"]))
                   if r["at"] >= now - timedelta(days=14)]
            _acc["v"] = {**evaluate.summary(res), "interval": evaluate.interval([r["error"] for r in res])}
        except Exception as e:
            print("accuracy:", e, flush=True)
            _acc["v"] = None
        _acc["t"] = time.time()
    return _acc["v"]


def prefs():
    try:
        with open(PREFS) as f:
            p = json.load(f)
    except (OSError, ValueError):
        p = {}
    return {"features": {"breast": True, "solids": False, "pump": True, **p.get("features", {})},
            "sug": p.get("sug", {}), "sex": p.get("sex", "boy"), "pump_remind": p.get("pump_remind", 3),
            "child_name": p.get("child_name", "")}


def child_name(c=None):
    """Navnet fra opsætningen, ellers fra databasen."""
    return prefs()["child_name"] or ((c or db().child() or {}).get("first_name") or "")


folke.display_name = child_name


def save_prefs(p):
    os.makedirs(os.path.dirname(PREFS), exist_ok=True)
    with open(PREFS, "w") as f:
        json.dump(p, f)


def suggestions(c, now, p):
    """Forslag til at tilpasse appen efter alder og brug. Intet ændres uden et svar fra dig."""
    out = []
    months = (now.date() - date.fromisoformat(c["birth_date"])).days / 30.44

    def open_(i):
        v = p["sug"].get(i)
        if not v:
            return True
        return v not in ("never", "done") and datetime.fromisoformat(v) < now

    if not p["features"]["solids"] and months >= 6 and open_("solids"):
        out.append({"id": "solids", "text": f"Han er nu {int(months)} måneder. Vil du tilføje «Fast føde» til Mad-kortet?"})
    if p["features"]["breast"] and open_("hide_breast"):
        fs = db().feedings(c["id"], now - timedelta(days=60))
        b = [folke.parse(f["start"]) for f in fs if "breast" in (f.get("method") or "")]
        if b and (now - max(b)).days >= 21:
            out.append({"id": "hide_breast", "text": f"Du har ikke registreret amning i {(now - max(b)).days // 7} uger. Skal Amning-knappen skjules?"})
    return out


def current_suggestions(c, now, p):
    if time.time() - _sc["t"] > 600:  # beregnes højst hvert 10. minut
        try:
            _sc["v"] = suggestions(c, now, p)
        except Exception:
            _sc["v"] = []
        _sc["t"] = time.time()
    return _sc["v"]


@app.post("/api/suggestion")
def answer_suggestion():
    d = request.get_json(silent=True) or {}
    i, a, p = d.get("id"), d.get("answer"), prefs()
    if i not in ("solids", "hide_breast") or a not in ("yes", "later", "never"):
        return jsonify(ok=False, error="Ugyldigt svar"), 400
    if a == "yes":
        p["features"]["solids" if i == "solids" else "breast"] = i == "solids"
        p["sug"][i] = "done"
    elif a == "later":
        p["sug"][i] = (datetime.now(TZ) + timedelta(days=30)).isoformat()
    else:
        p["sug"][i] = "never"
    save_prefs(p)
    _sc["t"] = 0
    return jsonify(ok=True)


@app.post("/api/feature")
def feature():
    d = request.get_json(silent=True) or {}
    if d.get("name") not in ("breast", "solids", "pump"):
        return jsonify(ok=False, error="Ukendt funktion"), 400
    p = prefs()
    p["features"][d["name"]] = bool(d.get("on"))
    save_prefs(p)
    return jsonify(ok=True)


def clean_name(v):
    name = " ".join(str(v or "").split())
    if not 1 <= len(name) <= 40:
        raise ValueError("Skriv barnets navn (højst 40 tegn)")
    return name


@app.post("/api/profile")
def profile():
    """Køn (vækstkurver) og/eller barnets navn."""
    d = request.get_json(silent=True) or {}
    if "sex" not in d and "name" not in d:
        return jsonify(ok=False, error="Intet at gemme"), 400
    p = prefs()
    if "sex" in d:
        if d["sex"] not in ("boy", "girl"):
            return jsonify(ok=False, error="Ugyldigt valg"), 400
        p["sex"] = d["sex"]
    if "name" in d:
        try:
            p["child_name"] = clean_name(d["name"])
        except ValueError as e:
            return jsonify(ok=False, error=str(e)), 400
    save_prefs(p)
    return jsonify(ok=True)


@app.post("/api/child")
def create_child():
    """Første opstart: opret barnet ud fra navn og fødselsdato."""
    if db().child():
        return jsonify(ok=False, error="Barnet findes allerede"), 409
    d = request.get_json(silent=True) or {}
    try:
        name = clean_name(d.get("name"))
        birth = date.fromisoformat(str(d.get("birth_date")))
    except ValueError as e:
        return jsonify(ok=False, error=str(e) if "navn" in str(e) else "Ugyldig fødselsdato"), 400
    if not datetime.now(TZ).date() - timedelta(days=6 * 365) <= birth <= datetime.now(TZ).date():
        return jsonify(ok=False, error="Ugyldig fødselsdato"), 400
    db().add_child(name, birth)
    p = prefs()
    p["child_name"] = name
    save_prefs(p)
    _sc["t"] = 0
    return jsonify(ok=True)


# ---------- Vækst (egen fil: growth.json) ----------
GROWTH = os.path.join(os.path.dirname(folke.STATE_FILE) or ".", "growth.json")
RANGES = {"w": (0.5, 30, "Vægt"), "l": (30, 120, "Længde"), "h": (25, 60, "Hovedomfang")}


def load_growth():
    try:
        with open(GROWTH) as f:
            return json.load(f)
    except (OSError, ValueError):
        return []


def save_growth(g):
    os.makedirs(os.path.dirname(GROWTH), exist_ok=True)
    with open(GROWTH, "w") as f:
        json.dump(g, f)


def clean_measure(d):
    try:
        day = date.fromisoformat(str(d.get("date")))
    except ValueError:
        raise ValueError("Ugyldig dato")
    if day > datetime.now(TZ).date():
        raise ValueError("Datoen ligger i fremtiden")
    out = {"date": day.isoformat()}
    for k, (lo, hi, name) in RANGES.items():
        v = d.get(k)
        if v in (None, ""):
            out[k] = None
            continue
        v = float(str(v).replace(",", "."))
        if not lo <= v <= hi:
            raise ValueError(f"{name} skal være mellem {lo} og {hi}")
        out[k] = v
    if all(out[k] is None for k in RANGES):
        raise ValueError("Skriv mindst én måling")
    return out


@app.get("/api/growth")
def growth():
    birth, sex = date.fromisoformat(get_child()["birth_date"]), prefs()["sex"]
    ents = sorted(load_growth(), key=lambda e: e["date"])
    for e in ents:
        e["m"] = round((date.fromisoformat(e["date"]) - birth).days / 30.4375, 2)
        for k in RANGES:
            e["p" + k] = who.percentile(k, sex, e["m"], e[k])
    age = (datetime.now(TZ).date() - birth).days / 30.4375
    upto = 12 if age < 9 else 24
    return jsonify(sex=sex, age_m=round(age, 1), entries=ents,
                   curves={k: who.curves(k, sex, upto) for k in RANGES})


@app.post("/api/growth")
@app.post("/api/growth/<int:gid>")
def growth_save(gid=None):
    try:
        m = clean_measure(request.get_json(silent=True) or {})
    except ValueError as e:
        return jsonify(ok=False, error=str(e)), 400
    g = load_growth()
    if gid is None:
        g.append({"id": max((e["id"] for e in g), default=0) + 1, **m})
    else:
        g = [{"id": gid, **m} if e["id"] == gid else e for e in g]
    save_growth(g)
    return jsonify(ok=True)


@app.delete("/api/growth/<int:gid>")
def growth_delete(gid):
    save_growth([e for e in load_growth() if e["id"] != gid])
    return jsonify(ok=True)


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
    db().edit_sleep(sid, s, e, bool(d["nap"]) if "nap" in d else None)
    return jsonify(ok=True)


@app.delete("/api/sleep/<int:sid>")
def delete_sleep(sid):
    c = get_child()
    s = next((x for x in db().sleeps(c["id"], datetime(2000, 1, 1, tzinfo=TZ)) if x["id"] == sid), None)
    if s and not s["nap"]:
        db().delete_wakes_between(c["id"], folke.parse(s["start"]), folke.parse(s["end"]))
    db().delete_sleep(sid)
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
        body = {"start": t, "end": t}
        if d.get("kind") == "bottle":
            amount = float(d["amount"])
            if not 0 < amount <= 500:
                raise ValueError
            body.update(type="formula" if d.get("milk") == "formula" else "breast milk",
                        method="bottle", amount=amount)
        elif d.get("kind") == "solid":
            body.update(type="solid food", method="parent fed", notes=str(d.get("note", ""))[:200])
        elif d.get("kind") in BREAST:
            body.update(type="breast milk", method=BREAST[d["kind"]])
        else:
            raise ValueError
    except (KeyError, ValueError):
        return jsonify(ok=False, error="Ugyldigt måltid"), 400
    db().add_feeding(get_child()["id"], **body)
    return jsonify(ok=True)


# ---------- Eksport ----------
@app.get("/api/export")
def export():
    """Alle data som JSON. Vækst og indstillinger ligger i growth.json og prefs.json."""
    data = {**db().export(), "growth": load_growth(), "prefs": prefs()}
    name = f"folke-{datetime.now(TZ):%Y-%m-%d}.json"
    return Response(json.dumps(data, ensure_ascii=False, indent=1), mimetype="application/json",
                    headers={"Content-Disposition": f'attachment; filename="{name}"'})


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


# ---------- Tavlen (easter egg: tryk på månen) ----------
# Fælles tegning for begge forældre. Streger gemmes som punkter i 0..1 (tavlen har fast format 3:4),
# så den ser ens ud på telefon og iPad. Ingen push: man ser den, når man åbner tavlen.
BOARD = os.path.join(os.path.dirname(folke.STATE_FILE) or ".", "board.json")
CHALK = ("#f4f1ea", "#ff8fa3", "#ffd27a", "#8fb0ff")
MAX_POINTS, MAX_TOTAL = 2000, 30000
_board_lock = threading.Lock()


def load_board():
    try:
        with open(BOARD) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {"version": 0, "strokes": [], "by": None, "updated": None}


def save_board(b, who):
    b["version"] += 1
    b["by"] = who if who in ("mor", "far") else None
    b["updated"] = datetime.now(TZ).isoformat(timespec="seconds")
    os.makedirs(os.path.dirname(BOARD) or ".", exist_ok=True)
    with open(BOARD, "w") as f:
        json.dump(b, f)
    return b


def clean_stroke(s):
    if not isinstance(s, dict) or s.get("c") not in CHALK:
        raise ValueError("Ugyldig farve")
    try:
        w = float(s.get("w"))
        pts = [[round(float(x), 4), round(float(y), 4)] for x, y in s.get("p") or []]
    except (TypeError, ValueError):
        raise ValueError("Ugyldig streg")
    if not 0.003 <= w <= 0.05:
        raise ValueError("Ugyldig stregtykkelse")
    if not 1 <= len(pts) <= MAX_POINTS or not all(0 <= v <= 1 for p in pts for v in p):
        raise ValueError("Ugyldig streg")
    return {"c": s["c"], "w": round(w, 4), "p": pts}


@app.get("/api/board")
def board():
    """Hele tavlen, eller kun {version}, hvis klienten allerede har den (?v=version)."""
    b = load_board()
    if request.args.get("v", type=int) == b["version"]:
        return jsonify(version=b["version"], same=True)
    return jsonify(b)


@app.post("/api/board/stroke")
def board_stroke():
    d = request.get_json(silent=True) or {}
    try:
        s = clean_stroke(d.get("stroke"))
    except ValueError as e:
        return jsonify(ok=False, error=str(e)), 400
    with _board_lock:
        b = load_board()
        if sum(len(x["p"]) for x in b["strokes"]) + len(s["p"]) > MAX_TOTAL:
            return jsonify(ok=False, error="Tavlen er fuld. Visk ud først"), 400
        b["strokes"].append(s)
        return jsonify(save_board(b, d.get("by")))


@app.post("/api/board/undo")
def board_undo():
    with _board_lock:
        b = load_board()
        if b["strokes"]:
            b["strokes"].pop()
            b = save_board(b, (request.get_json(silent=True) or {}).get("by"))
        return jsonify(b)


@app.post("/api/board/clear")
def board_clear():
    with _board_lock:
        b = load_board()
        b["strokes"] = []
        return jsonify(save_board(b, (request.get_json(silent=True) or {}).get("by")))


# ---------- Web push ----------
@app.get("/api/push/key")
def push_key():
    return jsonify(key=push.public_key())


@app.post("/api/push/subscribe")
def push_subscribe():
    d = request.get_json(silent=True) or {}
    try:
        n = push.subscribe(d.get("subscription"), d.get("origin", ""), d.get("name", ""))
    except ValueError as e:
        return jsonify(ok=False, error=str(e)), 400
    return jsonify(ok=True, devices=n)


@app.post("/api/push/unsubscribe")
def push_unsubscribe():
    push.unsubscribe((request.get_json(silent=True) or {}).get("endpoint", ""))
    return jsonify(ok=True)


@app.post("/api/push/kinds")
def push_kinds():
    """Hent ({endpoint}) eller sæt ({endpoint, kinds: {type: bool}, minutes: {lead, overdue}}) beskedtyper
    og minutter før/efter for denne enhed."""
    d = request.get_json(silent=True) or {}
    try:
        if isinstance(d.get("kinds"), dict):
            push.set_kinds(d.get("endpoint", ""), d["kinds"])
        if isinstance(d.get("minutes"), dict):
            push.set_minutes(d.get("endpoint", ""), d["minutes"])
        e = d.get("endpoint", "")
        return jsonify(ok=True, kinds=push.kinds(e), minutes=push.minutes(e),
                       options={"lead": push.LEAD_OPTIONS, "overdue": push.OVERDUE_OPTIONS})
    except KeyError:
        return jsonify(ok=False, error="Enheden er ikke tilmeldt"), 404
    except ValueError as e:
        return jsonify(ok=False, error=str(e)), 400


@app.post("/api/push/test")
def push_test():
    n = push.send("Folke-App", "Notifikationer virker på denne enhed.")
    return jsonify(ok=bool(n), sent=n, **({} if n else {"error": "Ingen enheder fik beskeden"}))


@app.get("/sw.js")
def service_worker():
    r = send_from_directory(".", "sw.js", mimetype="application/javascript")
    r.headers["Cache-Control"] = "no-cache"
    return r


@app.get("/")
def index():
    return send_from_directory(".", "index.html")


@app.errorhandler(Exception)
def err(e):
    if isinstance(e, HTTPException):  # fx 404 og 405: behold Flasks statuskode
        return jsonify(ok=False, error=e.description), e.code
    msg = str(e)
    if hasattr(e, "read"):  # HTTP-fejl: vis begrundelsen
        try:
            msg += " " + e.read().decode()[:200]
        except Exception:
            pass
    return jsonify(ok=False, error=msg), 409 if isinstance(e, LookupError) else 502


def tick():
    """Ét gennemløb: HA-sensor og notifikationer, påmindelse om udpumpning, daglig backup."""
    try:
        folke.main()
    except (Exception, SystemExit) as e:
        print("loop:", e, flush=True)
    try:
        pump_reminder(datetime.now(TZ))
    except Exception as e:
        print("pump:", e, flush=True)
    try:
        db().backup(os.path.join(os.path.dirname(db().path), "backup"))
    except Exception as e:
        print("backup:", e, flush=True)


def loop():
    while True:
        tick()
        time.sleep(60)


threading.Thread(target=loop, daemon=True).start()
