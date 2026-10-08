import CoreData
import Foundation
import Testing
@testable import FolkeCore

/// Mad, udpumpning, ret/slet og forslag (port af /api/feed, /api/pump, /api/sleep/<id> og /api/suggestion i app.py).
@MainActor @Suite("Registreringer", .serialized) struct RecordsTests {
    let d = day(2026, 6, 10)

    func store(birth: Date = day(2026, 2, 1)) throws -> FolkeStore {
        let s = try FolkeStore(inMemory: true)
        s.calendar = cph
        try s.createChild(name: "Folke", birthDate: birth)
        return s
    }

    @Test func retOgSletSoevn() throws {
        let s = try store()
        try s.startSleep(by: .mor, now: at(d, 12, 0))
        try s.stopSleep(now: at(d, 13, 0))
        let sl = try #require(s.todaySleeps(now: at(d, 14, 0)).first)
        #expect(throws: SleepRules.Failure.endBeforeStart) {
            try s.editSleep(sl, start: at(d, 13, 0), end: at(d, 12, 0), nap: true, now: at(d, 14, 0))
        }
        #expect(throws: SleepRules.Failure.endInFuture) {
            try s.editSleep(sl, start: at(d, 12, 0), end: at(d, 15, 0), nap: true, now: at(d, 14, 0))
        }
        try s.editSleep(sl, start: at(d, 11, 45), end: at(d, 13, 15), nap: false, now: at(d, 14, 0))
        #expect(sl.start == at(d, 11, 45) && sl.end == at(d, 13, 15) && !sl.nap)
        #expect(s.sleep(id: sl.id!) == sl)
        try s.delete(sl)
        #expect(s.todaySleeps(now: at(d, 14, 0)).isEmpty)
    }

    @Test func mad() throws {
        let s = try store()
        #expect(throws: RecordError.invalidMeal) { try s.addFeeding(.bottle, amountMl: 0, now: at(d, 9, 0)) }
        #expect(throws: RecordError.invalidMeal) { try s.addFeeding(.bottle, amountMl: 501, now: at(d, 9, 0)) }
        #expect(throws: RecordError.invalidMeal) { try s.addFeeding(.bottle, now: at(d, 9, 0)) }
        try s.addFeeding(.left, now: at(d, 8, 0))
        let f = try s.addFeeding(.bottle, amountMl: 120, milk: .formula, now: at(d, 9, 0))
        #expect(f.milk == "formula" && f.amountMl == 120)
        #expect(s.lastFeeding(now: at(d, 10, 10)) == f)
        #expect(s.lastBreastFeed(now: at(d, 10, 0)) == at(d, 8, 0))
        #expect(Format.lastFeed(kind: .bottle, amountMl: 120, time: at(d, 9, 0), now: at(d, 10, 10), calendar: cph)
                == "Flaske 120 ml kl. 09.00 · for 1 t 10 min siden")
        #expect(Format.lastFeed(kind: .right, amountMl: 0, time: at(d, 9, 0), now: at(d, 9, 5), calendar: cph)
                == "Amning, højre kl. 09.00 · for 5 min siden")
        let solid = try s.addFeeding(.solid, note: "  " + String(repeating: "g", count: 250), now: at(d, 11, 0))
        #expect(solid.note?.count == 200)
        #expect(solid.amountMl == 0 && solid.milk == nil)
    }

    @Test func udpumpning() throws {
        let s = try store()
        #expect(throws: RecordError.invalidAmount) { try s.addPumping(amountMl: 0) }
        #expect(throws: RecordError.invalidAmount) { try s.addPumping(amountMl: 1001) }
        #expect(throws: RecordError.invalidMinutes) { try s.addPumping(amountMl: 100, minutes: 181) }
        #expect(throws: RecordError.invalidMinutes) { try s.addPumping(amountMl: 100, minutes: 0) }
        try s.addPumping(amountMl: 90, at: at(plusDays(d, -1), 22, 0), now: at(d, 6, 0))
        try s.addPumping(amountMl: 120, side: .left, minutes: 15, at: at(d, 7, 0), now: at(d, 7, 0))
        let p = try s.addPumping(amountMl: 130.4, side: .both, now: at(d, 14, 20))
        let sum = s.pumpSummary(now: at(d, 15, 25))
        #expect(sum == PumpSummary(todayCount: 2, todayMl: 250, last: at(d, 14, 20)))
        #expect(Format.pumpSummary(sum, now: at(d, 15, 25), calendar: cph)
                == "I dag: 2 gange · 250 ml · sidst kl. 14.20 · for 1 t 5 min siden")
        #expect(Format.pumpSummary(.init(todayCount: 0, todayMl: 0, last: nil), now: d) == "Ingen udpumpninger endnu")
        #expect(Format.pumpSummary(.init(todayCount: 0, todayMl: 0, last: at(d, 9, 0)), now: at(d, 9, 30), calendar: cph)
                == "Ingen i dag · sidst kl. 09.00 · for 30 min siden")
        #expect(throws: RecordError.inFuture) {
            try s.editPumping(p, time: at(d, 16, 0), amountMl: 100, side: nil, minutes: nil, now: at(d, 15, 0))
        }
        try s.editPumping(p, time: at(d, 14, 0), amountMl: 100, side: nil, minutes: 10, now: at(d, 15, 0))
        #expect(p.amountMl == 100 && p.side == nil && p.minutes == 10)
    }

    @Test func forslagOgSvar() throws {
        let s = try store(birth: day(2025, 12, 1))
        let now = at(d, 12, 0)
        #expect(s.suggestions(now: now).map(\.id) == [.solids])
        try s.answer(.solids, .later, now: now)
        #expect(s.suggestions(now: now).isEmpty)
        #expect(s.suggestions(now: plusDays(now, 31)).map(\.id) == [.solids])
        try s.answer(.solids, .yes, now: now)
        #expect(s.settings()!.featureSolids)
        #expect(s.suggestions(now: plusDays(now, 31)).isEmpty)

        // Amning for 3 uger siden
        try s.addFeeding(.both, at: plusDays(now, -22), now: now)
        #expect(s.suggestions(now: now).map(\.id) == [.hideBreast])
        try s.answer(.hideBreast, .yes, now: now)
        #expect(!s.settings()!.featureBreast)
        #expect(s.suggestions(now: now).isEmpty)
    }

    @Test func dagensDele() {
        #expect(DayPart.of(start: at(d, 10, 59), nap: true, calendar: cph) == .morning)
        #expect(DayPart.of(start: at(d, 11, 0), nap: true, calendar: cph) == .day)
        #expect(DayPart.of(start: at(d, 15, 0), nap: true, calendar: cph) == .evening)
        #expect(DayPart.of(start: at(d, 9, 0), nap: false, calendar: cph) == .night)
        #expect(Format.time(at(d, 9, 5), calendar: cph) == "09.05")
    }

    @Test func dagensMaaltiderNyesteFoerst() throws {
        let s = try store()
        try s.addFeeding(.left, at: at(plusDays(d, -1), 22, 0), now: at(d, 12, 0))
        try s.addFeeding(.bottle, amountMl: 90, at: at(d, 7, 0), now: at(d, 12, 0))
        try s.addFeeding(.both, at: at(d, 10, 30), now: at(d, 12, 0))
        let today = s.todayFeedings(now: at(d, 12, 0))
        #expect(today.compactMap(\.kind) == ["both", "bottle"])
        #expect(s.feeding(id: today[0].id!) == today[0])
        #expect(Format.feedName(.left) == "Amning, venstre")
    }
}
