"""Teksterne i notifikationerne (messages.py): 10 milde varianter pr. slags, valgt ud fra tidspunktet."""
from datetime import datetime, timedelta

import messages
from folke import TZ

T = datetime(2026, 10, 17, 13, 40, tzinfo=TZ)


def test_ti_varianter_af_hver():
    for kind, lst in messages.ALL.items():
        assert len(lst) == 10 and len(set(lst)) == 10, kind


def test_samme_tidspunkt_samme_tekst_ellers_en_anden():
    a = messages.pick("soon_nap", T, "Folke", "13:40")
    assert a == messages.pick("soon_nap", T, "Folke", "13:40")
    assert a != messages.pick("soon_nap", T + timedelta(minutes=1), "Folke", "13:41")
    # Alle 10 kommer på skift
    assert len({messages.pick("late_nap", T + timedelta(minutes=i), "Folke") for i in range(10)}) == 10


def test_udfylder_navn_tid_og_timer():
    i = int(T.timestamp() // 60) % 10
    assert messages.pick("pump", T, t="09:15", h="3") == \
        messages.PUMP[i].replace("{t}", "09:15").replace("{h}", "3")
    for k in range(10):
        s = messages.pick("late_bed", T + timedelta(minutes=k), "")
        assert "{" not in s and s[0].isupper()
        assert "Folke" in messages.pick("soon_bed", T + timedelta(minutes=k), "Folke") or \
            "{name}" not in messages.SOON_BED[(i + k) % 10]


def test_uden_navn_den_lille():
    k = next(k for k in range(10) if messages.LATE_NAP[(int(T.timestamp() // 60) + k) % 10].startswith("{name}"))
    assert messages.pick("late_nap", T + timedelta(minutes=k), "").startswith("Den lille ")
