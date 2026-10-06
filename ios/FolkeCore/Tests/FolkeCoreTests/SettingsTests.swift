import Foundation
import Testing
@testable import FolkeCore

@MainActor @Suite("Indstillinger", .serialized) struct SettingsTests {
    let d = day(2026, 6, 10)

    func store() throws -> FolkeStore {
        let s = try FolkeStore(inMemory: true)
        s.calendar = cph
        try s.createChild(name: "Folke", birthDate: day(2026, 2, 1))
        return s
    }

    @Test func funktionerOgPaamindelse() throws {
        let s = try store()
        try s.setFeature(.pump, false)
        try s.setFeature(.solids, true)
        try s.setFeature(.breast, false)
        let set = try #require(s.settings())
        #expect(!set.featurePump && set.featureSolids && !set.featureBreast)
        try s.setPumpRemind(hours: 2.5)
        #expect(set.pumpRemindHours == 2.5)
        #expect(throws: SettingsError.invalidHours) { try s.setPumpRemind(hours: 13) }
        #expect(throws: SettingsError.invalidHours) { try s.setPumpRemind(hours: -1) }
    }

    @Test func navnOgKoen() throws {
        let s = try store()
        try s.renameChild("  Mads  ")
        #expect(s.child()?.name == "Mads")
        #expect(throws: SettingsError.invalidName) { try s.renameChild("   ") }
        #expect(s.child()?.name == "Mads")
        try s.setSex(.girl)
        #expect(s.child()?.sex == "girl")
    }

    @Test func senesteUdpumpning() throws {
        let s = try store()
        #expect(s.lastPumping(now: d) == nil)
        try s.addPumping(amountMl: 100, at: at(d, 9, 15), now: at(d, 9, 15))
        let p = try s.addPumping(amountMl: 100, at: at(d, 12, 0), now: at(d, 12, 0))
        let last = try #require(s.lastPumping(now: at(d, 13, 0)))
        #expect(last.id == p.id && last.time == at(d, 12, 0))
    }
}
