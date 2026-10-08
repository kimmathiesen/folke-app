"""Dagsplan: resten af dagen ud fra hans egne tal, og genberegning ved misset eller kort lur.

Samme syntetiske historik som test_predict.py: 10 dage med nat 19:30-06:30 og tre lure
(08:30-09:30, 12:00-13:30, 16:30-17:00). Vinduer: 120 efter natten, 150 efter 1. lur,
180 efter 2. lur, 150 efter 3. lur. Lurlængder: 60, 90 og 30 min.
"""
from datetime import date, timedelta

from folke import _Model, _normalize, _robust, nap_at_stop, plan_day, predict
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


def test_for_lidt_dagsoevn_rykker_kun_sengetiden_med_hans_egne_data():
    sleeps = history(naps_last_day=1) + [nap(500, (12, 0), (12, 40))]  # 2. lur kun 40 min (normalt 90)
    p = plan_day(sleeps, BIRTH, at(DAY, (12, 45)))
    # Ingen af hans dage har vist, at han sover tidligere efter for lidt dagsøvn: normal sengetid
    assert times(p) == [("lur", "15:40", "16:10"), ("sengetid", "19:30", None)]
    assert p["bed_shift"] == 0


def test_laert_rykning_naar_han_plejer_at_sove_tidligere():
    # 3 dage, hvor 2. lur kun varede 30 min, og han faldt i søvn 18:50 i stedet for 19:30
    days = []
    for s in history():
        d = s["start"].date()
        short_day = date(2026, 6, 6) <= d <= date(2026, 6, 8)
        if short_day and s["nap"] and s["start"].hour == 12:
            s = {**s, "end": at(d, (12, 30))}
        if short_day and not s["nap"] and d < DAY:
            s = {**s, "start": at(d, (18, 50))}
        days.append(s)
    m = _Model(days, 130)
    assert m.learned_shift() == 40
    today = history(naps_last_day=1) + [nap(500, (12, 0), (12, 30))]
    p = plan_day(days[:-3] + today[-2:], BIRTH, at(DAY, (12, 35)))
    assert p["bed_shift"] == 40


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


# ---------- Aftenlur (Folkes mønster, eksport 29/9-6/10 2026) ----------

def catnap_history(days=10, first=date(2026, 6, 1), night_as_nat=False):
    """Nat 21:00-07:00, lure 09:00-10:00, 12:30-14:00, 16:00-17:00 og aftenlur 18:45-19:30.
    night_as_nat: aftenluren er registreret som «nat» (startede efter 18), som i appen før rettelsen."""
    out, n = [], 0
    for i in range(days):
        d = first + timedelta(days=i)
        n += 1
        out.append({"id": n, "start": at(d - timedelta(days=1), (21, 0)), "end": at(d, (7, 0)), "nap": False})
        for (a, b) in [((9, 0), (10, 0)), ((12, 30), (14, 0)), ((16, 0), (17, 0)), ((18, 45), (19, 30))]:
            n += 1
            catnap = a == (18, 45)
            out.append({"id": n, "start": at(d, a), "end": at(d, b), "nap": not (catnap and night_as_nat)})
    return out


def test_aftenlur_laeres_og_sengetid_foelger_den():
    sleeps = catnap_history(night_as_nat=True)
    m = _Model(sorted(map(_normalize, sleeps), key=lambda s: s["start"]), 130)
    assert m.catnap_habit() and m.catnap_length() == 45 and m.evening_gap() == 90
    assert m.bed_min() == 21 * 60  # de korte «nætter» kl. 18:45 trækker ikke sengetiden ned


def test_kort_foerste_lur_giver_ikke_tidlig_sengetid():
    # Som Folke 6/10: kort første lur. Før: sidste lur droppet og sengetid rykket 60 min frem.
    day = date(2026, 6, 11)
    sleeps = catnap_history() + [{"id": 900, "start": at(day, (9, 0)), "end": at(day, (9, 20)), "nap": True}]
    p = plan_day(sleeps, BIRTH, at(day, (9, 25)))
    bed = p["items"][-1]
    assert bed["kind"] == "sengetid" and f"{bed['start']:%H:%M}" >= "21:00"
    assert p["bed_shift"] == 0
    assert any(x.get("catnap") or x["start"].hour >= 18 for x in p["items"][:-1])  # aftenluren er med


def test_aftenlur_planlaegges_naar_der_ikke_er_plads_til_en_hel_lur():
    day = date(2026, 6, 11)
    # Lang eftermiddagslur: næste hele lur (45 min + vindue) kan ikke nås, men en aftenlur kan
    sleeps = catnap_history() + [
        {"id": 900, "start": at(day, (9, 0)), "end": at(day, (10, 0)), "nap": True},
        {"id": 901, "start": at(day, (12, 30)), "end": at(day, (14, 0)), "nap": True},
        {"id": 902, "start": at(day, (16, 30)), "end": at(day, (18, 30)), "nap": True},
    ]
    p = plan_day(sleeps, BIRTH, at(day, (18, 35)))
    items = [(x["kind"], f"{x['start']:%H:%M}", x.get("end") and f"{x['end']:%H:%M}") for x in p["items"]]
    assert items[-1][0] == "sengetid" and items[-1][1] >= "21:00"
    assert p["bed_shift"] == 0


def test_efter_aftenluren_er_sengetid_hans_tid_vaagen_bagefter():
    day = date(2026, 6, 11)
    sleeps = catnap_history() + [
        {"id": 900 + i, "start": at(day, a), "end": at(day, b), "nap": True}
        for i, (a, b) in enumerate([((9, 0), (10, 0)), ((12, 30), (14, 0)), ((16, 0), (17, 0)), ((19, 0), (19, 45))])
    ]
    p = plan_day(sleeps, BIRTH, at(day, (19, 50)))
    assert times(p) == [("sengetid", "21:15", None)]  # 19:45 + 90 min


def test_kort_aftenlur_er_aftenluren_og_sengetid_foelger():
    """Folke 8/10: to korte lure (16:32 og 18:06). Den sidste er aftenluren, selvom den kun varede 20 min."""
    day = date(2026, 6, 11)
    sleeps = catnap_history() + [{"id": 900 + i, "start": at(day, a), "end": at(day, b), "nap": True} for i, (a, b) in
                                 enumerate([((9, 0), (10, 0)), ((12, 30), (14, 0)), ((16, 32), (16, 53)), ((18, 6), (18, 26))])]
    p = plan_day(sleeps, BIRTH, at(day, (18, 35)))
    assert times(p) == [("sengetid", "19:33", None)]  # 18:26 + 75 % af 90 min, ingen lur mere
    assert p["after_catnap"] and p["bed_shift"] == 0 and p["short"] is None
    assert predict(sleeps, BIRTH, at(day, (18, 35)))["window_min"] == 68


def test_tidlig_aftenlur_giver_tidligere_sengetid():
    """En hel aftenlur, der slutter tidligt: sengetiden følger hans tid vågen efter den, ikke det faste klokkeslæt."""
    day = date(2026, 6, 11)
    sleeps = catnap_history() + [{"id": 900 + i, "start": at(day, a), "end": at(day, b), "nap": True} for i, (a, b) in
                                 enumerate([((9, 0), (10, 0)), ((12, 30), (14, 0)), ((16, 0), (17, 0)), ((17, 40), (18, 25))])]
    assert times(plan_day(sleeps, BIRTH, at(day, (18, 30)))) == [("sengetid", "19:55", None)]
    # Er tiden gået, er det sengetid nu (ikke en ny lur)
    assert times(plan_day(sleeps, BIRTH, at(day, (20, 10)))) == [("sengetid", "20:10", None)]


def test_uden_aftenlur_gaelder_den_gamle_noedloesning():
    # Syntetisk historik uden aftenlur: misset sidste lur giver stadig tidligere sengetid
    m = _Model(history(), 130)
    assert not m.catnap_habit() and m.learned_shift() == 0


def test_gaet_paa_lur_eller_nat_ved_stop():
    d = date(2026, 6, 10)
    assert nap_at_stop(at(d, (18, 23)), at(d, (19, 10))) is True    # aftenlur
    assert nap_at_stop(at(d, (21, 7)), at(d + timedelta(days=1), (7, 40))) is False  # nat
    assert nap_at_stop(at(d, (19, 30)), at(d, (22, 0))) is False     # over 2 timer: nat
    assert nap_at_stop(at(d, (12, 0)), at(d, (13, 0))) is True


def test_manglende_nat_giver_ingen_hel_dag():
    sleeps = [s for s in catnap_history() if not (not s["nap"] and s["start"].date() == date(2026, 6, 4))]
    m = _Model(sleeps, 130)
    assert all(_mins_ok(d) for d in m.days)


def _mins_ok(d):
    return d[0] < 8 * 60  # en dag med en manglende nat ville have dobbelt så meget dagsøvn
