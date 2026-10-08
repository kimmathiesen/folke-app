"""Web push: notifikationer direkte til telefonen.

Virker på iPhone/iPad fra iOS 16.4, når appen er føjet til hjemmeskærmen og åbnet derfra, og i de
fleste andre browsere. Kræver https (fx via cloudflared). VAPID-nøglen laves første gang og ligger i
vapid.pem, abonnementerne (én pr. enhed) i push.json, begge ved siden af STATE_FILE.
"""
import base64
import json
import os
import threading
from datetime import datetime

from cryptography.hazmat.primitives import serialization

import folke

DIR = os.path.dirname(folke.STATE_FILE) or "."
KEY = os.path.join(DIR, "vapid.pem")
SUBS = os.path.join(DIR, "push.json")
FALLBACK_SUB = "mailto:folke-app@users.noreply.github.com"
# Beskedtyper pr. enhed: søvnbeskeder til, udpumpning fra, indtil man selv slår det til
DEFAULT_KINDS = {"sleep_soon": True, "overdue": True, "pump": False}
# Minutter før næste søvn («Tid til at slappe af») og efter («… virker meget frisk»), valgt pr. enhed.
# Standarden er serverens LEAD_MIN og OVERDUE_MIN (30 og 15).
LEAD_OPTIONS = [10, 15, 20, 30, 45, 60]
OVERDUE_OPTIONS = [5, 10, 15, 20, 30, 45]
_lock = threading.Lock()


def _vapid():
    from py_vapid import Vapid02

    with _lock:
        if not os.path.exists(KEY):
            os.makedirs(os.path.dirname(KEY) or ".", exist_ok=True)
            v = Vapid02()
            v.generate_keys()
            v.save_key(KEY)
    return Vapid02.from_file(KEY)


def public_key():
    """Offentlig nøgle i det format, browserens pushManager.subscribe() vil have."""
    raw = _vapid().public_key.public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def load():
    try:
        with open(SUBS) as f:
            return json.load(f)
    except (OSError, ValueError):
        return []


def _save(subs):
    os.makedirs(os.path.dirname(SUBS) or ".", exist_ok=True)
    with open(SUBS, "w") as f:
        json.dump(subs, f)


def subscribe(sub, origin="", name=""):
    """Gem (eller opdatér) en enheds abonnement. `sub` er PushSubscription.toJSON() fra browseren."""
    endpoint = (sub or {}).get("endpoint", "")
    keys = (sub or {}).get("keys") or {}
    if not endpoint.startswith("https://") or not keys.get("p256dh") or not keys.get("auth"):
        raise ValueError("Ugyldigt abonnement")
    with _lock:
        old = next((s for s in load() if s["endpoint"] == endpoint), {})
        subs = [s for s in load() if s["endpoint"] != endpoint]
        subs.append({"endpoint": endpoint, "keys": {"p256dh": keys["p256dh"], "auth": keys["auth"]},
                     "origin": origin if str(origin).startswith("https://") else "",
                     "name": str(name)[:60], "kinds": {**DEFAULT_KINDS, **old.get("kinds", {})},
                     "added": old.get("added") or datetime.now(folke.TZ).isoformat(timespec="seconds")})
        _save(subs)
    return len(subs)


def kinds(endpoint):
    """Beskedtyper for én enhed. KeyError, hvis enheden ikke er tilmeldt."""
    s = next((s for s in load() if s["endpoint"] == endpoint), None)
    if s is None:
        raise KeyError(endpoint)
    return {**DEFAULT_KINDS, **s.get("kinds", {})}


def set_kinds(endpoint, changes):
    with _lock:
        subs = load()
        s = next((s for s in subs if s["endpoint"] == endpoint), None)
        if s is None:
            raise KeyError(endpoint)
        s["kinds"] = {**DEFAULT_KINDS, **s.get("kinds", {}),
                      **{k: bool(v) for k, v in changes.items() if k in DEFAULT_KINDS}}
        _save(subs)


def timing(s):
    """(minutter før, minutter efter) for én enhed."""
    return s.get("lead", folke.LEAD_MIN), s.get("overdue", folke.OVERDUE_MIN)


def minutes(endpoint):
    """Minutter for én enhed. KeyError, hvis enheden ikke er tilmeldt."""
    s = next((s for s in load() if s["endpoint"] == endpoint), None)
    if s is None:
        raise KeyError(endpoint)
    lead, overdue = timing(s)
    return {"lead": lead, "overdue": overdue}


def set_minutes(endpoint, changes):
    """Sæt {"lead": 20} og/eller {"overdue": 30}. ValueError ved et tal uden for valgmulighederne."""
    allowed = {"lead": LEAD_OPTIONS + [folke.LEAD_MIN], "overdue": OVERDUE_OPTIONS + [folke.OVERDUE_MIN]}
    for k, v in changes.items():
        if k not in allowed or v not in allowed[k]:
            raise ValueError("Ugyldigt antal minutter")
    with _lock:
        subs = load()
        s = next((s for s in subs if s["endpoint"] == endpoint), None)
        if s is None:
            raise KeyError(endpoint)
        s.update({k: int(v) for k, v in changes.items()})
        _save(subs)


def wants(s, kind):
    return kind is None or {**DEFAULT_KINDS, **s.get("kinds", {})}.get(kind, True)


def unsubscribe(endpoint):
    with _lock:
        subs = load()
        _save([s for s in subs if s["endpoint"] != endpoint])


def active(kind=None):
    """Er der mindst én enhed, der vil have denne beskedtype (eller nogen besked overhovedet)?"""
    return any(wants(s, kind) for s in load())


def send(title, body, url="/", kind=None, endpoints=None):
    """Send til alle enheder, der vil have beskedtypen `kind` (None = alle, fx testbeskeden), evt. kun `endpoints`.
    Abonnementer, som push-tjenesten siger er udløbet (404/410), fjernes. Returnerer antal modtagere."""
    from pywebpush import WebPushException, webpush

    subs = [s for s in load() if wants(s, kind) and (endpoints is None or s["endpoint"] in endpoints)]
    if not subs:
        return 0
    key, data, ok, gone = _vapid(), json.dumps({"title": title, "body": body, "url": url}), 0, []
    for s in subs:
        try:
            webpush({"endpoint": s["endpoint"], "keys": s["keys"]}, data, vapid_private_key=key,
                    vapid_claims={"sub": s.get("origin") or FALLBACK_SUB}, ttl=3600, timeout=10)
            ok += 1
        except WebPushException as e:
            code = getattr(e.response, "status_code", None)
            if code in (404, 410):
                gone.append(s["endpoint"])
            else:
                print("push:", s.get("name") or s["endpoint"][:40], e, flush=True)
    for endpoint in gone:
        unsubscribe(endpoint)
    return ok
