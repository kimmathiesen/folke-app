"""Urolig søvn (rough.py): beskeden kommer kun, når søvnen er tydeligt dårligere end normalt."""
from datetime import date, datetime, timedelta

from folke import TZ
import rough

TODAY = date(2026, 10, 20)
NOW = datetime(2026, 10, 20, 10, 0, tzinfo=TZ)
BIRTH_4M = TODAY - timedelta(weeks=16)      # midt i 4-måneders perioden
BIRTH_6M = TODAY - timedelta(weeks=28)      # uden for de kendte perioder


def at(d, h, m=0):
    return datetime(d.year, d.month, d.day, h, m, tzinfo=TZ)


def history(days=18, bad=4, bad_naps=True, bad_wakes=True, wakes_before=True, gaps=()):
    """Normale dage (nat 19-6, lure 9-10.30 og 13-14.30) og `bad` urolige dage til sidst
    (korte lure på 25 min og 3 opvågninger om natten). Opvågninger før: én pr. nat."""
    sleeps, wakes, n = [], [], 0
    for i in range(days, 0, -1):
        d = TODAY - timedelta(days=i)
        if i in gaps:
            continue
        is_bad = i <= bad
        naps = [((9, 0), (9, 25)), ((11, 30), (11, 55)), ((14, 0), (14, 25))] if is_bad and bad_naps \
            else [((9, 0), (10, 30)), ((13, 0), (14, 30))]
        for a, b in naps:
            n += 1
            sleeps.append({"id": n, "start": at(d, *a), "end": at(d, *b), "nap": True})
        n += 1
        night = {"id": n, "start": at(d, 19), "end": at(d + timedelta(days=1), 6), "nap": False}
        sleeps.append(night)
        count = 3 if is_bad and bad_wakes else (1 if wakes_before else 0)
        for k in range(count):
            s = at(d, 22) + timedelta(hours=2 * k)
            wakes.append({"start": s, "end": s + timedelta(minutes=20)})
    return sleeps, wakes


def test_urolig_i_4_maaneders_perioden():
    s, w = history()
    r = rough.check(s, w, BIRTH_4M, NOW, "Folke")
    assert r["key"] == "p-4m" and r["period"] == "4m"
    assert r["reasons"] == ["wakes", "naps", "short", "day"]  # 3 x 20 min vågen gør ikke natten 15 % kortere
    assert r["text"].startswith("Folke har sovet lidt dårligere de seneste dage (flere opvågninger om natten, ")
    assert "4-måneders søvnregressionen" in r["text"] and r["text"].endswith("Husk, at du gør det godt.")


def test_urolig_uden_for_perioderne():
    s, w = history()
    r = rough.check(s, w, BIRTH_6M, NOW, "")
    assert r["period"] is None and r["key"] == "u-2026-43"
    assert r["text"].startswith("Jeres barn har sovet") and "tænder, forkølelse" in r["text"]


def test_i_perioden_men_sover_fint():
    s, w = history(bad=0)
    assert rough.check(s, w, BIRTH_4M, NOW) is None


def test_en_daarlig_dag_er_ikke_nok():
    s, w = history(bad=1)
    assert rough.check(s, w, BIRTH_4M, NOW) is None


def test_kun_en_ting_er_ikke_nok():
    # Kun flere opvågninger (lurene er normale): én ting, ingen besked
    s, w = history(bad_naps=False)
    assert rough.check(s, w, BIRTH_4M, NOW) is None


def test_opvaagninger_taeller_kun_hvis_de_ogsaa_blev_registreret_foer():
    # Kun lurene er dårligere (kortere lure, flere korte, mindre dagsøvn = 3 ting); opvågninger findes kun nu
    s, w = history(bad_wakes=True, wakes_before=False)
    r = rough.check(s, w, BIRTH_4M, NOW)
    assert r["reasons"] == ["naps", "short", "day"]


def test_for_lidt_data():
    s, w = history(days=8)
    assert rough.check(s, w, BIRTH_4M, NOW) is None
    s, w = history(gaps=(1, 2))   # kun 2 af de seneste 4 dage registreret
    assert rough.check(s, w, BIRTH_4M, NOW) is None


def test_perioderne():
    assert rough.period(TODAY - timedelta(weeks=13, days=6), TODAY) is None
    assert rough.period(TODAY - timedelta(weeks=14), TODAY)[0] == "4m"
    assert rough.period(TODAY - timedelta(weeks=40), TODAY)[0] == "8m"
    assert rough.period(TODAY - timedelta(weeks=52), TODAY)[0] == "12m"
    assert rough.period(TODAY - timedelta(weeks=80), TODAY)[0] == "18m"
    assert rough.period(TODAY - timedelta(weeks=104), TODAY)[0] == "24m"
    assert rough.period(TODAY - timedelta(weeks=30), TODAY) is None
