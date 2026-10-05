import Foundation
import Testing
@testable import FolkeCore

/// Vækst og udpumpningshistorik (clean_measure, /api/growth og /api/pump/history i app.py).
@MainActor @Suite("Vækst og historik", .serialized) struct HistoryTests {
    let d = day(2026, 6, 10)

    func store(birth: Date = day(2026, 2, 1)) throws -> FolkeStore {
        let s = try FolkeStore(inMemory: true)
        s.calendar = cph
        try s.createChild(name: "Folke", birthDate: birth)
        return s
    }

    @Test func maalingerValideres() throws {
        let s = try store()
        #expect(throws: GrowthError.inFuture) { try s.saveGrowth(date: plusDays(d, 1), values: [.weight: 6], now: d) }
        #expect(throws: GrowthError.empty) { try s.saveGrowth(date: d, values: [.weight: nil], now: d) }
        #expect(throws: GrowthError.outOfRange(.weight)) { try s.saveGrowth(date: d, values: [.weight: 0.4], now: d) }
        #expect(throws: GrowthError.outOfRange(.length)) { try s.saveGrowth(date: d, values: [.length: 121], now: d) }
        #expect(throws: GrowthError.outOfRange(.head)) { try s.saveGrowth(date: d, values: [.head: 24], now: d) }
        #expect(GrowthError.outOfRange(.weight).errorDescription == "Vægt skal være mellem 0,5 og 30")
        #expect(GrowthError.outOfRange(.head).errorDescription == "Hovedomfang skal være mellem 25 og 60")
    }

    @Test func maalingerMedAlderOgPercentil() throws {
        let s = try store(birth: day(2026, 1, 1))
        try s.saveGrowth(date: day(2026, 1, 1), values: [.weight: 3.3464, .length: 49.8842], now: d)
        let g = try s.saveGrowth(date: day(2026, 4, 2), values: [.weight: 6.0], now: d)
        let pts = s.growthPoints()
        #expect(pts.count == 2)
        #expect(pts[0].months == 0 && pts[0].percentiles[.weight] == 50 && pts[0].percentiles[.length] == 50)
        #expect(pts[0].values[.head] == nil)
        #expect(pts[1].months == 2.99) // 91 dage / 30,4375
        #expect(pts[1].percentiles[.weight] == WHO.percentile(.weight, .boy, month: 2.99, value: 6))
        // Ret: længde tilføjes, vægt fjernes
        try s.saveGrowth(g, date: day(2026, 4, 2), values: [.weight: nil, .length: 60], now: d)
        let p = s.growthPoints()[1]
        #expect(p.values == [.length: 60])
        // Pige-kurver
        try s.setSex(.girl)
        #expect(s.growthPoints()[0].percentiles[.weight] == WHO.percentile(.weight, .girl, month: 0, value: 3.3464))
        try s.delete(g)
        #expect(s.growthPoints().count == 1)
    }

    @Test func udpumpningPrDag() throws {
        let s = try store()
        let now = at(d, 15, 0)
        try s.addPumping(amountMl: 100, at: at(plusDays(d, -14), 12, 0), now: now) // uden for de 14 dage
        try s.addPumping(amountMl: 100, at: at(plusDays(d, -13), 9, 0), now: now)
        try s.addPumping(amountMl: 150.4, at: at(plusDays(d, -13), 23, 59), now: now)
        try s.addPumping(amountMl: 300, at: at(plusDays(d, -1), 0, 0), now: now)
        try s.addPumping(amountMl: 80, at: at(d, 8, 0), now: now)
        let h = s.pumpHistory(now: now)
        #expect(h.days.count == 14)
        #expect(h.days.first == PumpDay(date: plusDays(d, -13), ml: 250, count: 2))
        #expect(h.days.last == PumpDay(date: d, ml: 80, count: 1))
        #expect(h.days[12] == PumpDay(date: plusDays(d, -1), ml: 300, count: 1))
        #expect(h.avgMl == 275) // (250 + 300) / 2, i dag tæller ikke
        #expect(try store().pumpHistory(now: now).avgMl == nil)
    }

    @Test func tekster() {
        #expect(Format.pumpDescription(amountMl: 150, side: .both, minutes: 15) == "150 ml · begge · 15 min")
        #expect(Format.pumpDescription(amountMl: 90.4, side: nil, minutes: 0) == "90 ml")
        #expect(Format.hours(2.5) == "2½")
        #expect(Format.hours(3) == "3")
        #expect(Format.number(6.45) == "6,45")
        #expect(Format.number(1000) == "1000")
    }
}
