#!/usr/bin/env python3
"""Måling af forudsigelsen mod historikken (backtest).

For hver søvn i historikken: lad som om klokken er lige efter, han vågnede sidst, regn dagsplanen ud fra det,
der var registreret indtil da, og sammenlign første punkt med det tidspunkt, han faktisk faldt i søvn.
Fejl i minutter: positiv = han faldt i søvn senere end forudsagt.

    python evaluate.py folke-2026-10-06.json      # rapport for en eksport fra /api/export
"""
import json
import statistics
import sys
from datetime import date, datetime, timedelta

import folke

MIN_HISTORY_DAYS = 3  # de første dage er der for lidt at regne på


def _mins(a, b):
    return (b - a).total_seconds() / 60


def backtest(sleeps, birth_date, predictor=None, history_days=None):
    """Fejl for hver søvn, der kan forudsiges. sleeps: dicts med id, start, end, nap (datetime med tidszone).
    predictor(sleeps, birth_date, now) -> {"kind", "time"} (standard: første punkt i dagsplanen)."""
    history_days = history_days or folke.HISTORY_DAYS
    if predictor is None:
        def predictor(hist, birth, now):
            p = folke.plan_day(hist, birth, now, replan=False)
            return p and {"kind": p["items"][0]["kind"], "time": p["items"][0]["start"]}
    sleeps = sorted(sleeps, key=lambda s: s["start"])
    if not sleeps:
        return []
    first = sleeps[0]["start"]
    out = []
    for i, s in enumerate(sleeps):
        prev = [x for x in sleeps[:i] if x["end"] <= s["start"]]
        if not prev or _mins(first, s["start"]) < MIN_HISTORY_DAYS * 1440:
            continue
        now = prev[-1]["end"] + timedelta(minutes=1)
        if _mins(now, s["start"]) > 8 * 60:
            continue  # et hul i registreringerne, ikke et vågenvindue
        hist = [x for x in prev if x["end"] >= now - timedelta(days=history_days)]
        p = predictor(hist, birth_date, now)
        if not p:
            continue
        out.append({"at": s["start"], "actual": "lur" if s["nap"] else "sengetid", "predicted": p["kind"],
                    "error": _mins(p["time"], s["start"])})
    return out


def summary(results):
    """Gennemsnitlig og typisk afvigelse, andel inden for 15/30 min, skævhed og fejlklassificering."""
    if not results:
        return {"n": 0}
    errs = [r["error"] for r in results]
    absolute = [abs(e) for e in errs]
    return {
        "n": len(results),
        "mean_abs": round(statistics.mean(absolute), 1),
        "median_abs": round(statistics.median(absolute), 1),
        "within_15": round(sum(a <= 15 for a in absolute) / len(absolute), 2),
        "within_30": round(sum(a <= 30 for a in absolute) / len(absolute), 2),
        "bias": round(statistics.median(errs), 1),
        "wrong_kind": sum(r["actual"] != r["predicted"] for r in results),
    }


def interval(errors, min_half=10, max_half=45):
    """Usikkerhed ud fra hans egne fejl: (tidligst, senest) i minutter omkring forudsigelsen.
    Den midterste halvdel af fejlene (25.-75. percentil), dog mindst ±10 og højst ±45 min."""
    if len(errors) < 8:
        return (-20, 20)
    q = statistics.quantiles(errors, n=4)
    lo, hi = min(q[0], -min_half), max(q[2], min_half)
    return (max(round(lo), -max_half), min(round(hi), max_half))


def load_export(path):
    e = json.load(open(path))
    p = lambda t: datetime.fromisoformat(t).astimezone(folke.TZ)  # noqa: E731
    sleeps = [{"id": s["id"], "start": p(s["start"]), "end": p(s["end"]), "nap": bool(s["nap"])} for s in e["sleep"]]
    return sleeps, date.fromisoformat(e["child"][0]["birth_date"])


def report(sleeps, birth):
    res = backtest(sleeps, birth)
    lines = [f"Dagsplanen: {summary(res)}"]
    for kind in ("lur", "sengetid"):
        lines.append(f"  {kind}: {summary([r for r in res if r['actual'] == kind])}")
    lines.append(f"Interval ud fra fejlene: {interval([r['error'] for r in res])} min")
    worst = sorted(res, key=lambda r: -abs(r["error"]))[:5]
    lines.append("Største afvigelser: " + ", ".join(
        f"{r['at']:%d/%m %H:%M} {r['actual']} {r['error']:+.0f}" for r in worst))
    return "\n".join(lines)


if __name__ == "__main__":
    print(report(*load_export(sys.argv[1])))
