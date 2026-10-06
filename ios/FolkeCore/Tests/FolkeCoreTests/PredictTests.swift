import Foundation
import Testing
@testable import FolkeCore

/// Port af tests/test_predict.py: 10 syntetiske dage med nat + 3 lure og faste vågenvinduer.
let cph: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Copenhagen")!
    return c
}()

func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    cph.date(from: DateComponents(year: y, month: m, day: d))!
}

func at(_ d: Date, _ h: Int, _ m: Int) -> Date {
    cph.date(bySettingHour: h, minute: m, second: 0, of: d)!
}

func plusDays(_ d: Date, _ n: Int) -> Date {
    cph.date(byAdding: .day, value: n, to: d)!
}

func id(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
}

let birth = day(2026, 2, 1)
let night = (19, 30)
// (start, slut) pr. lur. Vågenvinduer: 120 min efter natten, 150 efter lur 1, 180 efter lur 2,
// 150 efter lur 3 (frem til sengetid 19:30)
let naps = [((8, 30), (9, 30)), ((12, 0), (13, 30)), ((16, 30), (17, 0))]

func history(days: Int = 10, first: Date = day(2026, 6, 1), napsLastDay: Int = 3) -> [SleepSample] {
    var out: [SleepSample] = []
    var n = 0
    for i in 0..<days {
        let d = plusDays(first, i)
        n += 1
        out.append(.init(id: id(n), start: at(plusDays(d, -1), night.0, night.1), end: at(d, 6, 30), nap: false))
        for (s, e) in naps.prefix(i == days - 1 ? napsLastDay : 3) {
            n += 1
            out.append(.init(id: id(n), start: at(d, s.0, s.1), end: at(d, e.0, e.1), nap: true))
        }
    }
    return out
}

func predict(_ s: [SleepSample], _ now: Date) -> Prediction? {
    Predictor.predict(s, birthDate: birth, now: now, calendar: cph)
}

@Suite("Forudsigelse") struct PredictTests {
    @Test func ingenDataGiverNil() {
        #expect(predict([], Date()) == nil)
    }

    @Test func egetMoensterEfterAndenLur() throws {
        let sleeps = history(napsLastDay: 2)
        let lastDay = day(2026, 6, 10)
        let p = try #require(predict(sleeps, at(lastDay, 14, 0)))
        #expect(p.kind == .nap)
        #expect(p.windowMin == 180)
        #expect(p.time == at(lastDay, 16, 30))
        #expect(p.source == .position(2))
        #expect(p.source.text == "eget mønster (position 2)")
        #expect(p.lastID == sleeps.last!.id)
    }

    @Test func morgenBrugerVindueEfterNatten() throws {
        let sleeps = history(napsLastDay: 0)
        let p = try #require(predict(sleeps, at(day(2026, 6, 10), 7, 0)))
        #expect(p.kind == .nap)
        #expect(p.windowMin == 120)
        #expect(p.time == at(day(2026, 6, 10), 8, 30))
    }

    @Test func sengetidEfterSidsteLur() throws {
        let sleeps = history(napsLastDay: 3)
        let lastDay = day(2026, 6, 10)
        let p = try #require(predict(sleeps, at(lastDay, 17, 30)))
        #expect(p.kind == .bedtime)
        #expect(p.time == at(lastDay, night.0, night.1)) // median af aftensøvne
    }

    @Test func sengetidDerErGaaetFlyttesTilVinduetsSlut() throws {
        // Kl. 22 efter en sen lur, der sluttede 20:45: sengetiden 19:30 er gået, så det er sengetid, når vinduet er gået
        var sleeps = history(napsLastDay: 3)
        let lastDay = day(2026, 6, 10)
        sleeps.append(.init(id: id(99), start: at(lastDay, 20, 0), end: at(lastDay, 20, 45), nap: true))
        let p = try #require(predict(sleeps, at(lastDay, 22, 0)))
        #expect(p.kind == .bedtime)
        #expect(p.time == at(lastDay, 20, 45).addingTimeInterval(Double(p.windowMin) * 60))
        #expect(p.time > at(lastDay, night.0, night.1))
    }

    @Test func raekkefoelgeErLigegyldig() {
        let sleeps = history(napsLastDay: 2)
        let now = at(day(2026, 6, 10), 14, 0)
        #expect(predict(sleeps.reversed(), now) == predict(sleeps, now))
    }

    @Test func aldersbaseretStandardUdenNokData() throws {
        let d = day(2026, 6, 10)
        let sleeps = [SleepSample(id: id(1), start: at(plusDays(d, -1), night.0, night.1), end: at(d, 6, 0), nap: false)]
        let now = at(d, 6, 30)
        let p = try #require(predict(sleeps, now))
        let age = cph.dateComponents([.day], from: birth, to: cph.startOfDay(for: now)).day! // 129 dage = 4,2 mdr.
        #expect(age == 129)
        #expect(p.source == .ageDefault)
        #expect(p.windowMin == Predictor.defaultWindow(ageDays: age))
        #expect(p.windowMin == 120)
        #expect(p.time == at(d, 8, 0))
    }

    @Test func gennemsnitAfAlleVinduerSomFallback() throws {
        // Seks lure i træk: hver position har kun én prøve, men der er 5 vinduer i alt
        var sleeps: [SleepSample] = []
        var t = at(day(2026, 6, 10), 6, 0)
        for i in 0..<6 {
            sleeps.append(.init(id: id(i + 1), start: t, end: t.addingTimeInterval(30 * 60), nap: true))
            t = t.addingTimeInterval(Double(30 + 60 + i * 2) * 60)
        }
        let p = try #require(predict(sleeps, sleeps.last!.end))
        #expect(p.source == .allWindows)
        #expect(p.windowMin == 64) // median af 60, 62, 64, 66, 68
    }

    @Test func urimeligeHullerIgnoreres() throws {
        // Huller under 20 min eller over 8 timer tæller ikke med: kun 3 gyldige vinduer af 5,
        // så der er ikke nok til gennemsnittet, og aldersstandarden bruges
        var sleeps: [SleepSample] = []
        var t = at(day(2026, 6, 10), 0, 0)
        for (i, gap) in [60, 10, 60, 600, 60, 0].enumerated() {
            sleeps.append(.init(id: id(i + 1), start: t, end: t.addingTimeInterval(30 * 60), nap: true))
            t = t.addingTimeInterval(Double(30 + gap) * 60)
        }
        let p = try #require(predict(sleeps, sleeps.last!.end))
        #expect(p.source == .ageDefault)
    }

    @Test(arguments: [(0, 60), (70, 75), (100, 90), (150, 120), (250, 150), (330, 180), (500, 210), (700, 270)])
    func defaultWindow(days: Int, mins: Int) {
        #expect(Predictor.defaultWindow(ageDays: days) == mins)
    }

    // Ud over Python-testene

    @Test func medianSomPython() {
        #expect(Predictor.median([3, 1, 2]) == 2)
        #expect(Predictor.median([4, 1, 3, 2]) == 2.5)
    }

    @Test func gaetLurEllerNat() {
        let d = day(2026, 6, 10)
        #expect(Predictor.napGuess(at(d, 4, 59), calendar: cph) == false)
        #expect(Predictor.napGuess(at(d, 5, 0), calendar: cph) == true)
        #expect(Predictor.napGuess(at(d, 17, 59), calendar: cph) == true)
        #expect(Predictor.napGuess(at(d, 18, 0), calendar: cph) == false)
    }
}
