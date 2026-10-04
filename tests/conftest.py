"""Fælles opsætning: miljøet sættes, før napper/app importeres (de læser env ved import)."""
import os
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

os.environ.update({
    "BB_URL": "http://bb.test",
    "BB_TOKEN": "test",
    "HA_URL": "",
    "HA_NOTIFY": "",
    "CHILD_ID": "",
    "TZ": "Europe/Copenhagen",
    "STATE_FILE": os.path.join(tempfile.mkdtemp(), "state.json"),
})

import napper  # noqa: E402

# app.py starter en baggrundstråd ved import, som kalder napper.main() - ingen netværk i tests
napper.main = lambda: None
