import Foundation
import Testing
@testable import FolkeCore

/// Port af tests/test_predict.py fra før dagsplanen (commit eeaa016^): gratisudgaven af forudsigelsen.
@Suite("Forudsigelse, gratis") struct BasicPredictTests {
    func basic(_ s: [SleepSample], _ now: Date) -> Prediction? {
        Predictor.basic(s, birthDate: birth, now: now, calendar: cph)
    }

    @Test func ingenDataGiverNil() {
        #expect(basic([], Date()) == nil)
    }

    @Test func egetMoensterEfterAndenLur() throws {
        let s = history(napsLastDay: 2), d = day(2026, 6, 10)
        let p = try #require(basic(s, at(d, 14, 0)))
        #expect(p.kind == .nap && p.windowMin == 180 && p.time == at(d, 16, 30))
        #expect(p.source == .position(2) && p.pos == 2 && p.lastID == s.last!.id)
    }

    @Test func morgenBrugerVindueEfterNatten() throws {
        let p = try #require(basic(history(napsLastDay: 0), at(day(2026, 6, 10), 7, 0)))
        #expect(p.kind == .nap && p.windowMin == 120 && p.time == at(day(2026, 6, 10), 8, 30))
    }

    @Test func sengetidEfterSidsteLur() throws {
        let d = day(2026, 6, 10)
        let p = try #require(basic(history(napsLastDay: 3), at(d, 17, 30)))
        #expect(p.kind == .bedtime && p.time == at(d, 19, 30) && p.bedBasis == .own)
    }

    @Test func sengetidDerErGaaetFlyttesTilVinduetsSlut() throws {
        let d = day(2026, 6, 10)
        let s = history(napsLastDay: 3) + [.init(id: id(99), start: at(d, 20, 0), end: at(d, 20, 45), nap: true)]
        let p = try #require(basic(s, at(d, 22, 0)))
        #expect(p.kind == .bedtime)
        #expect(p.time == at(d, 20, 45).addingTimeInterval(Double(p.windowMin) * 60) && p.time > at(d, 19, 30))
    }

    @Test func raekkefoelgeErLigegyldig() {
        let s = history(napsLastDay: 2), now = at(day(2026, 6, 10), 14, 0)
        #expect(basic(s.reversed(), now) == basic(s, now))
    }

    @Test func aldersbaseretStandardUdenNokData() throws {
        let d = day(2026, 6, 10)
        let s = [SleepSample(id: id(1), start: at(plusDays(d, -1), 19, 30), end: at(d, 6, 0), nap: false)]
        let p = try #require(basic(s, at(d, 6, 30)))
        #expect(p.source == .ageDefault && p.bedBasis == .default)
        #expect(p.windowMin == 120 && p.time == at(d, 8, 0))
    }

    @Test func gennemsnitAfAlleVinduerSomFallback() throws {
        var s: [SleepSample] = []
        var t = at(day(2026, 6, 10), 6, 0)
        for i in 0..<6 {
            s.append(.init(id: id(i + 1), start: t, end: t.addingTimeInterval(30 * 60), nap: true))
            t = t.addingTimeInterval(Double(30 + 60 + i * 2) * 60)
        }
        let p = try #require(basic(s, s.last!.end))
        #expect(p.source == .allWindows && p.windowMin == 64)
    }

    @Test func urimeligeHullerIgnoreres() throws {
        var s: [SleepSample] = []
        var t = at(day(2026, 6, 10), 0, 0)
        for (i, gap) in [60, 10, 60, 600, 60, 0].enumerated() {
            s.append(.init(id: id(i + 1), start: t, end: t.addingTimeInterval(30 * 60), nap: true))
            t = t.addingTimeInterval(Double(30 + gap) * 60)
        }
        #expect(try #require(basic(s, s.last!.end)).source == .ageDefault)
    }
}
