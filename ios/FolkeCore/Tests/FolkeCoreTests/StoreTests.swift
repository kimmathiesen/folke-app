import CoreData
import Foundation
import Testing
@testable import FolkeCore

@MainActor @Suite("Model og datalag", .serialized) struct StoreTests {
    func store() throws -> FolkeStore {
        let s = try FolkeStore(inMemory: true)
        s.calendar = cph
        return s
    }

    @Test func modellenOverholderCloudKitsKrav() {
        for e in FolkeModel.shared.entities {
            #expect(e.uniquenessConstraints.isEmpty, "\(e.name!)")
            for a in e.attributesByName.values {
                #expect(a.isOptional || a.defaultValue != nil, "\(e.name!).\(a.name)")
            }
            for r in e.relationshipsByName.values {
                #expect(r.isOptional, "\(e.name!).\(r.name)")
                #expect(r.inverseRelationship != nil, "\(e.name!).\(r.name)")
            }
            if e.name != "Settings" {
                #expect(e.attributesByName["id"]?.attributeType == .UUIDAttributeType, "\(e.name!)")
            }
        }
        #expect(Set(FolkeModel.shared.entities.compactMap(\.name)) ==
                ["Family", "Child", "Sleep", "Feeding", "Pumping", "Growth", "Stroke", "Settings", "NightWake"])
    }

    @Test func barnOgIndstillinger() throws {
        let s = try store()
        #expect(s.child() == nil)
        let c = try s.createChild(name: "Folke", birthDate: day(2026, 2, 1), sex: .boy, now: day(2026, 2, 10))
        #expect(s.child() == c)
        let set = try #require(s.settings())
        #expect(set.child == c)
        let fam = try #require(s.family())
        #expect(set.featureBreast && !set.featureSolids && set.featurePrediction && fam.featurePump)
        #expect(fam.pumpRemindHours == 3 && c.family == fam)
        set.answers = [.solids: .snoozed(until: day(2026, 7, 1)), .hideBreast: .never]
        #expect(set.answers[.solids] == .snoozed(until: day(2026, 7, 1)))
        #expect(set.answers[.hideBreast] == .never)
    }

    @Test func startOgStop() throws {
        let s = try store()
        try s.createChild(name: "Folke", birthDate: day(2026, 2, 1))
        let d = day(2026, 6, 10)
        let sl = try s.startSleep(by: .mor, now: at(d, 12, 0))
        #expect(sl.nap)
        #expect(sl.createdBy == "mor")
        #expect(sl.child == s.child())
        #expect(s.runningSleep() == sl)
        #expect(s.prediction(now: at(d, 12, 30)) == nil) // ingen forudsigelse, mens søvnen kører
        // Et tryk mere starter ikke en ny
        #expect(try s.startSleep(by: .far, now: at(d, 12, 1)) == sl)
        try s.stopSleep(now: at(d, 13, 0))
        #expect(s.runningSleep() == nil)
        #expect(sl.end == at(d, 13, 0))
        #expect(s.todaySleeps(now: at(d, 14, 0)) == [sl])
        #expect(s.awakeSince(now: at(d, 14, 0)) == at(d, 13, 0))
        let p = try #require(s.prediction(now: at(d, 13, 5)))
        #expect(p.source == .ageDefault)
    }

    @Test func glemteTrykAfvises() throws {
        let s = try store()
        try s.createChild(name: "Folke", birthDate: day(2026, 2, 1))
        let d = day(2026, 6, 10)
        try s.startSleep(by: .mor, now: at(d, 12, 0))
        #expect(throws: SleepRules.Failure.wakeBeforeStart(at(d, 12, 0))) {
            try s.stopSleep(at: at(d, 11, 0), now: at(d, 13, 0))
        }
        try s.stopSleep(at: at(d, 12, 45), nap: true, now: at(d, 13, 0))
        #expect(throws: SleepRules.Failure.startBeforePreviousEnd(at(d, 12, 45))) {
            try s.startSleep(at: at(d, 12, 30), by: .mor, now: at(d, 14, 0))
        }
        let late = try s.startSleep(at: at(d, 19, 0), by: .far, now: at(d, 19, 20))
        #expect(!late.nap) // kl. 19 gættes som nat
    }

    @Test func soevnOverMidnatErMedIDag() throws {
        let s = try store()
        try s.createChild(name: "Folke", birthDate: day(2026, 2, 1))
        let d = day(2026, 6, 10)
        try s.startSleep(at: at(plusDays(d, -1), 19, 30), by: .mor, now: at(plusDays(d, -1), 19, 31))
        try s.stopSleep(now: at(d, 6, 30))
        try s.startSleep(by: .mor, now: at(d, 8, 30))
        try s.stopSleep(now: at(d, 9, 30))
        #expect(s.todaySleeps(now: at(d, 10, 0)).count == 2)
        #expect(s.todaySleeps(now: at(plusDays(d, 1), 10, 0)).isEmpty)
    }
}
