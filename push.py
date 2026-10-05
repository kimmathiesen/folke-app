"""Web push: notifikationer direkte til telefonen uden Home Assistant.

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

import napper

DIR = os.path.dirname(napper.STATE_FILE) or "."
KEY = os.path.join(DIR, "vapid.pem")
SUBS = os.path.join(DIR, "push.json")
FALLBACK_SUB = "mailto:folke-app@users.noreply.github.com"
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
        subs = [s for s in load() if s["endpoint"] != endpoint]
        subs.append({"endpoint": endpoint, "keys": {"p256dh": keys["p256dh"], "auth": keys["auth"]},
                     "origin": origin if str(origin).startswith("https://") else "",
                     "name": str(name)[:60], "added": datetime.now(napper.TZ).isoformat(timespec="seconds")})
        _save(subs)
    return len(subs)


def unsubscribe(endpoint):
    with _lock:
        subs = load()
        _save([s for s in subs if s["endpoint"] != endpoint])


def active():
    return bool(load())


def send(title, body, url="/"):
    """Send til alle enheder. Abonnementer, som push-tjenesten siger er udløbet (404/410), fjernes.
    Returnerer antal enheder, der fik beskeden."""
    from pywebpush import WebPushException, webpush

    subs = load()
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
