import Foundation
import Testing
@testable import FolkeCore

@Suite("Regler") struct RulesTests {
    let d = day(2026, 6, 10)

    @Test func genitiv() {
        #expect(Format.genitive("Folke") == "Folkes")
        #expect(Format.genitive("Mads") == "Mads'")
        #expect(Format.genitive("Max") == "Max'")
        #expect(Format.genitive("Liz") == "Liz'")
        #expect(Format.greeting(name: "Folke", role: .mor) == "Hej Folkes mor")
        #expect(Format.greeting(name: "", role: .far) == "Baby Søvn")
        #expect(Format.greeting(name: "Folke", role: nil) == "Baby Søvn")
    }

    @Test func formater() {
        #expect(Format.duration(minutes: 45) == "45 min")
        #expect(Format.duration(minutes: 80) == "1 t 20 min")
        #expect(Format.duration(minutes: 60) == "1 t")
        #expect(Format.duration(minutes: 120) == "2 t")
        #expect(Format.counter(seconds: 3725) == "01:02:05")
        #expect(Format.clock(at(d, 9, 5), calendar: cph) == "09:05")
        #expect(Format.cleanName("  Folke   Bo ") == "Folke Bo")
        #expect(Format.cleanName("   ") == nil)
        #expect(Format.cleanName(String(repeating: "a", count: 41)) == nil)
    }

    @Test func klokkeslaetIFremtidenErIGaar() {
        let now = at(d, 0, 10)
        #expect(SleepRules.resolve(hour: 23, minute: 50, now: now, calendar: cph) == at(plusDays(d, -1), 23, 50))
        #expect(SleepRules.resolve(hour: 0, minute: 5, now: now, calendar: cph) == at(d, 0, 5))
    }

    @Test func glemteTryk() {
        #expect(throws: SleepRules.Failure.startBeforePreviousEnd(at(d, 10, 0))) {
            try SleepRules.checkStart(at(d, 9, 0), previousEnd: at(d, 10, 0))
        }
        #expect(throws: Never.self) { try SleepRules.checkStart(at(d, 11, 0), previousEnd: at(d, 10, 0)) }
        #expect(throws: Never.self) { try SleepRules.checkStart(at(d, 11, 0), previousEnd: nil) }
        #expect(throws: SleepRules.Failure.wakeBeforeStart(at(d, 10, 0))) {
            try SleepRules.checkWake(at(d, 10, 0), start: at(d, 10, 0))
        }
    }

    @Test func retSoevn() {
        let now = at(d, 12, 0)
        #expect(throws: SleepRules.Failure.endBeforeStart) {
            try SleepRules.checkEdit(start: at(d, 11, 0), end: at(d, 10, 0), now: now)
        }
        #expect(throws: SleepRules.Failure.endInFuture) {
            try SleepRules.checkEdit(start: at(d, 11, 0), end: at(d, 12, 2), now: now)
        }
        #expect(throws: Never.self) { try SleepRules.checkEdit(start: at(d, 11, 0), end: at(d, 12, 0), now: now) }
    }

    @Test func forslagFastFoede() {
        let birth = day(2025, 12, 1) // 6 mdr. den 10. juni
        let s = Suggestions.compute(now: d, birthDate: birth, sex: .boy, solids: false, breast: false,
                                    lastBreastFeed: nil, answers: [:], calendar: cph)
        #expect(s.map(\.id) == [.solids])
        #expect(s[0].text == "Han er nu 6 måneder. Vil du tilføje «Fast føde» til Mad-kortet?")
        // Allerede slået til, eller for ung
        #expect(Suggestions.compute(now: d, birthDate: birth, sex: .boy, solids: true, breast: false,
                                    lastBreastFeed: nil, answers: [:], calendar: cph).isEmpty)
        #expect(Suggestions.compute(now: d, birthDate: day(2026, 1, 1), sex: .boy, solids: false, breast: false,
                                    lastBreastFeed: nil, answers: [:], calendar: cph).isEmpty)
    }

    @Test func forslagSkjulAmning() {
        let s = Suggestions.compute(now: d, birthDate: day(2026, 2, 1), sex: .girl, solids: false, breast: true,
                                    lastBreastFeed: plusDays(d, -22), answers: [:], calendar: cph)
        #expect(s.map(\.text) == ["Du har ikke registreret amning i 3 uger. Skal Amning-knappen skjules?"])
        #expect(Suggestions.compute(now: d, birthDate: day(2026, 2, 1), sex: .girl, solids: false, breast: true,
                                    lastBreastFeed: plusDays(d, -20), answers: [:], calendar: cph).isEmpty)
    }

    @Test func svarPaaForslag() {
        let later = Suggestions.stored(for: .later, now: d)
        #expect(!Suggestions.open(later, now: plusDays(d, 29)))
        #expect(Suggestions.open(later, now: plusDays(d, 31)))
        #expect(!Suggestions.open(.never, now: d))
        #expect(!Suggestions.open(Suggestions.stored(for: .yes, now: d), now: d))
        #expect(Suggestions.open(nil, now: d))
    }

    @Test func farverInterpoleres() {
        #expect(Theme.ringColor(hour: 12) == RGB(255, 214, 125))
        #expect(Theme.ringColor(hour: 2.5) == RGB(84.5, 93, 219))
        #expect(Theme.sky(hour: 0).top == RGB(15, 24, 48))
        #expect(Theme.nap == RGB(169, 194, 255))
    }
}
