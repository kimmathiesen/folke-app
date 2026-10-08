import Foundation
import Testing
@testable import FolkeCore

/// Port af tests/test_dayplan.py: dagsplan, genberegning ved misset eller kort lur, aftenlur og lært rykning.
/// Samme syntetiske historik som PredictTests: nat 19:30-06:30 og lure 08:30-09:30, 12:00-13:30, 16:30-17:00.
@Suite("Dagsplan") struct DayPlanTests {
    let DAY = day(2026, 6, 10)

    func nap(_ i: Int, _ s: (Int, Int), _ e: (Int, Int), on d: Date? = nil) -> SleepSample {
        let d = d ?? DAY
        return SleepSample(id: id(i), start: at(d, s.0, s.1), end: at(d, e.0, e.1), nap: true)
    }

    func plan(_ s: [SleepSample], _ now: Date, running: Date? = nil) -> DayPlan {
        DayPlanner.plan(s, birthDate: birth, now: now, running: running, calendar: cph)!
    }

    func times(_ p: DayPlan) -> [String] {
        p.items.map { "\($0.kind.rawValue) \(Format.clock($0.start, calendar: cph))"
            + ($0.end.map { "-" + Format.clock($0, calendar: cph) } ?? "") }
    }

    func model(_ s: [SleepSample], ageDays: Int = 130) -> DayPlanner.Model {
        DayPlanner.Model(s.map { DayPlanner.normalize(.init(id: $0.id, start: $0.start, end: $0.end, nap: $0.nap), cph) }
            .sorted { $0.start < $1.start }, ageDays: ageDays, calendar: cph)
    }

    @Test func heleDagenOmMorgenen() {
        let p = plan(history(napsLastDay: 0), at(DAY, 7, 0))
        #expect(times(p) == ["lur 08:30-09:30", "lur 12:00-13:30", "lur 16:30-17:00", "sengetid 19:30"])
        #expect(p.naps == 3 && p.bedShift == 0 && p.missedAt == nil)
    }

    @Test func planenFoelgerDetFaktiskeOpvaagningstidspunkt() {
        let s = history(napsLastDay: 0) + [nap(500, (8, 30), (10, 0))] // 1. lur 30 min længere end normalt
        #expect(times(plan(s, at(DAY, 10, 5))).first == "lur 12:30-14:00") // 150 min efter han vågnede
    }

    @Test func kortLurTaellerIkkeOgNaesteVindueErKortere() throws {
        let s = history(napsLastDay: 1) + [nap(500, (11, 0), (11, 15))] // 15 min i barnevognen
        let p = plan(s, at(DAY, 11, 20))
        #expect(p.short == 15)
        #expect(times(p)[0] == "lur 13:07-14:37") // 75 % af 150 min, og det er stadig «2. lur» (90 min)
        #expect(times(p)[1] == "sengetid 18:30") // uden aftenlur: nødløsningen (3. lur kan ikke nås)
        #expect(p.bedShift == 60)
        let pr = try #require(Predictor.predict(s, birthDate: birth, now: at(DAY, 11, 20), calendar: cph))
        #expect(pr.kind == .nap && Format.clock(pr.time, calendar: cph) == "13:07" && pr.short == 15)
        #expect(Format.why(pr) == "Vågen ca. 1 t 52 min efter en kort lur på 15 min (kortere end normalt)")
    }

    @Test func missetLurGenberegnerResten() throws {
        let s = history(napsLastDay: 1) // 2. lur var planlagt 12:00
        let p = plan(s, at(DAY, 12, 20))
        #expect(p.missedAt == at(DAY, 12, 0))
        #expect(times(p) == ["lur 12:20-13:50", "lur 16:50-17:20", "sengetid 19:50"])
        // Beskederne bruger stadig det oprindelige tidspunkt
        #expect(try #require(Predictor.predict(s, birthDate: birth, now: at(DAY, 12, 20), calendar: cph)).time == at(DAY, 12, 0))
    }

    @Test func missetLurIkkeFoerDerErGaaetEtKvarter() {
        let p = plan(history(napsLastDay: 1), at(DAY, 12, 10))
        #expect(p.missedAt == nil && times(p)[0] == "lur 12:00-13:30")
    }

    @Test func missetSidsteLurGiverTidligSengetidUdenAftenlur() {
        let p = plan(history(napsLastDay: 2), at(DAY, 17, 50)) // 3. lur var planlagt 16:30
        #expect(p.missedAt == at(DAY, 16, 30))
        #expect(times(p) == ["sengetid 18:30"] && p.bedShift == 60)
    }

    @Test func forLidtDagsoevnRykkerKunSengetidenMedHansEgneData() throws {
        let s = history(napsLastDay: 1) + [nap(500, (12, 0), (12, 40))] // 2. lur kun 40 min (normalt 90)
        let p = plan(s, at(DAY, 12, 45))
        #expect(times(p) == ["lur 15:40-16:10", "sengetid 19:30"])
        #expect(p.bedShift == 0)
    }

    @Test func laertRykningNaarHanPlejerAtSoveTidligere() {
        // 3 dage, hvor 2. lur kun varede 30 min, og han faldt i søvn 18:50 i stedet for 19:30
        let days: [SleepSample] = history().map { s in
            var s = s
            let d = cph.startOfDay(for: s.start)
            let shortDay = d >= day(2026, 6, 6) && d <= day(2026, 6, 8)
            if shortDay && s.nap && cph.component(.hour, from: s.start) == 12 { s.end = at(d, 12, 30) }
            if shortDay && !s.nap && d < DAY { s.start = at(d, 18, 50) }
            return s
        }
        #expect(model(days).learnedShift() == 40)
        let today = history(napsLastDay: 1) + [nap(500, (12, 0), (12, 30))]
        let p = plan(Array(days.dropLast(3)) + today.suffix(2), at(DAY, 12, 35))
        #expect(p.bedShift == 40)
    }

    @Test func lurIGang() {
        let s = history(napsLastDay: 1)
        let p = plan(s, at(DAY, 12, 30), running: at(DAY, 12, 0))
        #expect(p.wake == at(DAY, 13, 30)) // 2. lur plejer at vare 90 min
        #expect(times(p) == ["lur 16:30-17:00", "sengetid 19:30"])
        let late = plan(s, at(DAY, 13, 45), running: at(DAY, 12, 0))
        #expect(late.wake == at(DAY, 13, 45)) // sover længere end normalt: planen regnes fra nu
    }

    @Test func korteLurePaavirkerIkkeHansTal() {
        var withCatnap: [SleepSample] = []
        for s in history() {
            withCatnap.append(s)
            if s.nap && cph.component(.hour, from: s.start) == 8 { // hver dag en kort lur 10:47-11:02
                let d = cph.startOfDay(for: s.start)
                withCatnap.append(.init(id: UUID(), start: at(d, 10, 47), end: at(d, 11, 2), nap: true))
            }
        }
        let m = model(withCatnap)
        #expect(!m.allGaps.contains(77) && !m.allGaps.contains(58))
        #expect(Set(m.napsPerDay) == [3] && !m.allLengths.contains(15))
        #expect(m.window(2).0 == 180 && m.window(0).0 == 120)
    }

    @Test func afvigendeVinduerSorteresFra() {
        #expect(DayPlanner.robust([150, 150, 150, 400], 7) == [150, 150, 150])
        #expect(DayPlanner.robust([150, 400], 7) == [150, 400])
    }

    @Test func ingenSoevnIngenPlan() {
        #expect(DayPlanner.plan([], birthDate: birth, now: at(DAY, 7, 0), calendar: cph) == nil)
    }

    // MARK: Aftenlur (Folkes mønster, eksport 29/9-6/10 2026)

    /// Nat 21:00-07:00, lure 09:00-10:00, 12:30-14:00, 16:00-17:00 og aftenlur 18:45-19:30.
    func catnapHistory(days: Int = 10, first: Date = day(2026, 6, 1), nightAsNat: Bool = false) -> [SleepSample] {
        var out: [SleepSample] = []
        var n = 0
        for i in 0..<days {
            let d = plusDays(first, i)
            n += 1
            out.append(.init(id: id(n), start: at(plusDays(d, -1), 21, 0), end: at(d, 7, 0), nap: false))
            for (a, b) in [((9, 0), (10, 0)), ((12, 30), (14, 0)), ((16, 0), (17, 0)), ((18, 45), (19, 30))] {
                n += 1
                let catnap = a == (18, 45)
                out.append(.init(id: id(n), start: at(d, a.0, a.1), end: at(d, b.0, b.1), nap: !(catnap && nightAsNat)))
            }
        }
        return out
    }

    @Test func aftenlurLaeresOgSengetidFoelgerDen() {
        let m = model(catnapHistory(nightAsNat: true))
        #expect(m.catnapHabit() && m.catnapLength() == 45 && m.eveningGap() == 90)
        #expect(m.bedMin() == 21 * 60) // de korte «nætter» kl. 18:45 trækker ikke sengetiden ned
    }

    @Test func kortFoersteLurGiverIkkeTidligSengetid() throws {
        let d = day(2026, 6, 11)
        let s = catnapHistory() + [nap(900, (9, 0), (9, 20), on: d)]
        let p = plan(s, at(d, 9, 25))
        let bed = try #require(p.items.last)
        #expect(bed.kind == .bedtime && bed.start >= at(d, 21, 0))
        #expect(p.bedShift == 0)
        #expect(p.items.dropLast().contains { $0.catnap || cph.component(.hour, from: $0.start) >= 18 })
    }

    @Test func aftenlurPlanlaeggesNaarDerIkkeErPladsTilEnHelLur() throws {
        let d = day(2026, 6, 11)
        let s = catnapHistory() + [nap(900, (9, 0), (10, 0), on: d), nap(901, (12, 30), (14, 0), on: d),
                                   nap(902, (16, 30), (18, 30), on: d)]
        let p = plan(s, at(d, 18, 35))
        let bed = try #require(p.items.last)
        #expect(bed.kind == .bedtime && bed.start >= at(d, 21, 0))
        #expect(p.bedShift == 0)
    }

    @Test func efterAftenlurenErSengetidHansTidVaagenBagefter() {
        let d = day(2026, 6, 11)
        let s = catnapHistory() + [((9, 0), (10, 0)), ((12, 30), (14, 0)), ((16, 0), (17, 0)), ((19, 0), (19, 45))]
            .enumerated().map { nap(900 + $0.offset, $0.element.0, $0.element.1, on: d) }
        #expect(times(plan(s, at(d, 19, 50))) == ["sengetid 21:15"]) // 19:45 + 90 min
    }

    @Test func udenAftenlurGaelderDenGamleNoedloesning() {
        let m = model(history())
        #expect(!m.catnapHabit() && m.learnedShift() == 0)
    }

    @Test func gaetPaaLurEllerNatVedStop() {
        let d = DAY
        #expect(DayPlanner.napAtStop(start: at(d, 18, 23), end: at(d, 19, 10), calendar: cph)) // aftenlur
        #expect(!DayPlanner.napAtStop(start: at(d, 21, 7), end: at(plusDays(d, 1), 7, 40), calendar: cph)) // nat
        #expect(!DayPlanner.napAtStop(start: at(d, 19, 30), end: at(d, 22, 0), calendar: cph)) // over 2 timer
        #expect(DayPlanner.napAtStop(start: at(d, 12, 0), end: at(d, 13, 0), calendar: cph))
    }

    @Test func manglendeNatGiverIngenHelDag() {
        let s = catnapHistory().filter { !(!$0.nap && cph.isDate($0.start, inSameDayAs: day(2026, 6, 4))) }
        #expect(model(s).days.allSatisfy { $0.slept < 8 * 60 })
    }

    // MARK: Kort aftenlur (Folke 8/10 2026: to korte lure kl. 16.32 og 18.06)

    func todayNaps(_ spans: [((Int, Int), (Int, Int))], on d: Date) -> [SleepSample] {
        spans.enumerated().map { nap(900 + $0.offset, $0.element.0, $0.element.1, on: d) }
    }

    @Test func kortAftenlurErAftenlurenOgSengetidFoelger() throws {
        let d = day(2026, 6, 11)
        let s = catnapHistory() + todayNaps([((9, 0), (10, 0)), ((12, 30), (14, 0)), ((16, 32), (16, 53)), ((18, 6), (18, 26))], on: d)
        let p = plan(s, at(d, 18, 35))
        #expect(times(p) == ["sengetid 19:33"]) // 18:26 + 75 % af 90 min, ingen lur mere
        #expect(p.afterCatnap && p.bedShift == 0 && p.short == nil)
        let pr = try #require(Predictor.predict(s, birthDate: birth, now: at(d, 18, 35), calendar: cph))
        #expect(pr.windowMin == 68 && Format.why(pr) == "Vågen ca. 1 t 8 min efter aftenluren")
    }

    @Test func tidligAftenlurGiverTidligereSengetid() {
        let d = day(2026, 6, 11)
        let s = catnapHistory() + todayNaps([((9, 0), (10, 0)), ((12, 30), (14, 0)), ((16, 0), (17, 0)), ((17, 40), (18, 25))], on: d)
        #expect(times(plan(s, at(d, 18, 30))) == ["sengetid 19:55"])
        #expect(times(plan(s, at(d, 20, 10))) == ["sengetid 20:10"]) // tiden er gået: sengetid nu, ikke en ny lur
    }
}
