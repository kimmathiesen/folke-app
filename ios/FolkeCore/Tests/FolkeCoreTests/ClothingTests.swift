import Foundation
import Testing
@testable import FolkeCore

@MainActor @Suite("Tøjstørrelse", .serialized) struct ClothingTests {
    let birthDay = day(2026, 1, 1)

    @Test func stoerrelseEfterLaengde() {
        #expect(Clothing.size(forLength: 61.4) == 62)
        #expect(Clothing.size(forLength: 62) == 62)
        #expect(Clothing.size(forLength: 62.1) == 68)
        #expect(Clothing.size(forLength: 99) == nil)
    }

    @Test func fremskrivesLangsSinPercentil() throws {
        // Median ved fødslen (z = 0): ved 3 mdr. er han medianen for 3 mdr. (61,43 cm), altså str. 62
        let now = cph.date(byAdding: .day, value: 91, to: birthDay)! // 91 dage = 2,99 mdr.
        let e = try #require(Clothing.estimate(length: 49.8842, measuredAt: birthDay, birthDate: birthDay, sex: .boy,
                                                now: now, calendar: cph))
        #expect(abs(e.lengthToday - WHO.value(.length, .boy, month: 91 / 30.4375, z: 0)) < 0.001)
        #expect(e.size == 62 && e.nextSize == 68 && e.percentile == 50)
        // Medianen passerer 62 cm ved ca. 3,23 mdr. (98-99 dage)
        let days = cph.dateComponents([.day], from: birthDay, to: e.nextSizeFrom!).day!
        #expect((97...100).contains(days))
    }

    @Test func storBarnFoelgerSinHoejePercentil() throws {
        // P97 ved fødslen giver en større størrelse end medianen senere
        let p97 = WHO.value(.length, .boy, month: 0, z: 1.8808)
        let now = cph.date(byAdding: .day, value: 91, to: birthDay)!
        let e = try #require(Clothing.estimate(length: p97, measuredAt: birthDay, birthDate: birthDay, sex: .boy,
                                                now: now, calendar: cph))
        #expect(e.size == 68)
    }

    @Test func udenLaengdeEllerEfter24MdrIntetSkoen() throws {
        let s = try FolkeStore(inMemory: true)
        s.calendar = cph
        try s.createChild(name: "Folke", birthDate: birthDay)
        try s.saveGrowth(date: day(2026, 2, 1), values: [.weight: 4.5], now: day(2026, 3, 1))
        #expect(s.clothingEstimate(now: day(2026, 3, 1)) == nil)
        try s.saveGrowth(date: day(2026, 2, 1), values: [.length: 55], now: day(2026, 3, 1))
        #expect(s.clothingEstimate(now: day(2026, 3, 1)) != nil)
        #expect(s.clothingEstimate(now: day(2028, 2, 1)) == nil)
    }

    @Test func tekst() {
        let d = day(2026, 6, 10)
        #expect(Format.untilText(plusDays(d, 35), now: d, calendar: cph) == "om ca. 5 uger")
        #expect(Format.untilText(plusDays(d, 3), now: d, calendar: cph) == "om ca. 3 dage")
        #expect(Format.untilText(d, now: d, calendar: cph) == "nu")
    }
}
