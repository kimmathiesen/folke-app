"""Dagsplan: resten af dagen ud fra hans egne tal, og genberegning ved misset eller kort lur.

Samme syntetiske historik som test_predict.py: 10 dage med nat 19:30-06:30 og tre lure
(08:30-09:30, 12:00-13:30, 16:30-17:00). Vinduer: 120 efter natten, 150 efter 1. lur,
180 efter 2. lur, 150 efter 3. lur. Lurlængder: 60, 90 og 30 min.
"""
from datetime import date, timedelta

from folke import _Model, _robust, plan_day, predict
from test_predict import BIRTH, at, history

DAY = date(2026, 6, 10)


def nap(i, start, end):
    return {"id": i, "start": at(DAY, start), "end": at(DAY, end), "nap": True}


def times(plan):
    return [(x["kind"], f"{x['start']:%H:%M}", x.get("end") and f"{x['end']:%H:%M}") for x in plan["items"]]


def test_hele_dagen_om_morgenen():
    p = plan_day(history(naps_last_day=0), BIRTH, at(DAY, (7, 0)))
    assert times(p) == [("lur", "08:30", "09:30"), ("lur", "12:00", "13:30"), ("lur", "16:30", "17:00"),
                        ("sengetid", "19:30", None)]
    assert p["naps"] == 3 and p["bed_shift"] == 0 and p["missed_at"] is None


def test_planen_foelger_det_faktiske_opvaagningstidspunkt():
    sleeps = history(naps_last_day=0) + [nap(500, (8, 30), (10, 0))]  # 1. lur 30 min længere end normalt
    p = plan_day(sleeps, BIRTH, at(DAY, (10, 5)))
    assert times(p)[0] == ("lur", "12:30", "14:00")  # 150 min efter han vågnede


def test_kort_lur_taeller_ikke_og_naeste_vindue_er_kortere():
    sleeps = history(naps_last_day=1) + [nap(500, (11, 0), (11, 15))]  # 15 min i barnevognen
    p = plan_day(sleeps, BIRTH, at(DAY, (11, 20)))
    assert p["short"] == 15
    # 75 % af 150 min efter den korte lur, og det er stadig «2. lur» (90 min)
    assert times(p)[0] == ("lur", "13:07", "14:37")
    # 3. lur ville skubbe sengetiden langt over 19:30, så den droppes, og sengetid rykkes frem
    assert times(p)[1] == ("sengetid", "18:30", None)
    assert p["bed_shift"] == 60
    pr = predict(sleeps, BIRTH, at(DAY, (11, 20)))
    assert pr["kind"] == "lur" and f"{pr['time']:%H:%M}" == "13:07" and pr["short"] == 15


def test_misset_lur_genberegner_resten_af_dagen():
    sleeps = history(naps_last_day=1)  # 2. lur var planlagt 12:00
    now = at(DAY, (12, 20))
    p = plan_day(sleeps, BIRTH, now)
    assert p["missed_at"] == at(DAY, (12, 0))
    assert times(p) == [("lur", "12:20", "13:50"), ("lur", "16:50", "17:20"), ("sengetid", "19:50", None)]
    # Beskederne bruger stadig det oprindelige tidspunkt, så «virker meget frisk» kommer kl. 12:15
    assert predict(sleeps, BIRTH, now)["time"] == at(DAY, (12, 0))


def test_misset_lur_ikke_foer_der_er_gaaet_et_kvarter():
    p = plan_day(history(naps_last_day=1), BIRTH, at(DAY, (12, 10)))
    assert p["missed_at"] is None and times(p)[0][1] == "12:00"


def test_misset_sidste_lur_giver_tidlig_sengetid():
    sleeps = history(naps_last_day=2)  # 3. lur var planlagt 16:30
    p = plan_day(sleeps, BIRTH, at(DAY, (17, 50)))
    assert p["missed_at"] == at(DAY, (16, 30))
    assert times(p) == [("sengetid", "18:30", None)] and p["bed_shift"] == 60


def test_for_lidt_dagsoevn_rykker_sengetiden_frem():
    sleeps = history(naps_last_day=1) + [nap(500, (12, 0), (12, 40))]  # 2. lur kun 40 min (normalt 90)
    p = plan_day(sleeps, BIRTH, at(DAY, (12, 45)))
    assert times(p) == [("lur", "15:40", "16:10"), ("sengetid", "19:05", None)]
    assert p["bed_shift"] == 25  # halvdelen af 50 min underskud
    # og beskeden om sengetid følger med
    after = sleeps + [nap(501, (15, 40), (16, 10))]
    pr = predict(after, BIRTH, at(DAY, (16, 15)))
    assert pr["kind"] == "sengetid" and f"{pr['time']:%H:%M}" == "19:05" and pr["bed_shift"] == 25


def test_lur_i_gang():
    sleeps = history(naps_last_day=1)
    p = plan_day(sleeps, BIRTH, at(DAY, (12, 30)), running=at(DAY, (12, 0)))
    assert f"{p['wake']:%H:%M}" == "13:30"  # 2. lur plejer at vare 90 min
    assert times(p) == [("lur", "16:30", "17:00"), ("sengetid", "19:30", None)]
    late = plan_day(sleeps, BIRTH, at(DAY, (13, 45)), running=at(DAY, (12, 0)))
    assert f"{late['wake']:%H:%M}" == "13:45"  # sover længere end normalt: planen regnes fra nu


def test_korte_lure_paavirker_ikke_hans_tal():
    days = history()
    with_catnap = []
    for s in days:
        with_catnap.append(s)
        if s["nap"] and s["start"].hour == 8:  # hver dag en kort lur 10:47-11:02 mellem 1. og 2. lur
            d = s["start"].date()
            with_catnap.append({"id": s["id"] + 1000, "nap": True, "start": at(d, (10, 47)), "end": at(d, (11, 2))})
    m = _Model(with_catnap, 130)
    assert 77 not in m.all_gaps and 58 not in m.all_gaps  # vinduerne lige før og efter den korte lur
    assert set(m.naps_per_day) == {3} and 15 not in m.all_lengths
    assert m.window(2)[0] == 180 and m.window(0)[0] == 120


def test_afvigende_vinduer_sorteres_fra():
    assert _robust([150, 150, 150, 400], 7) == [150, 150, 150]
    assert _robust([150, 400], 7) == [150, 400]  # for få til at se, hvad der er normalt


def test_ingen_soevn_ingen_plan():
    assert plan_day([], BIRTH, at(DAY, (7, 0))) is None
