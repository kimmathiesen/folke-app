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

    @Test func hentetSøvnGiverSammeSomEnkeltopslag() throws {
        let s = try store()
        try s.createChild(name: "Folke", birthDate: day(2026, 2, 1))
        let d = day(2026, 6, 20)
        // 20 dage med lure og nætter (også ældre end de 10 dage, forudsigelsen bruger), i går uden nat
        for i in (1...20).reversed() {
            let x = plusDays(d, -i)
            try s.startSleep(at: at(x, 9, 30 + i % 3 * 5), by: .mor, now: at(x, 9, 45))
            try s.stopSleep(at: at(x, 10, 40), nap: true, now: at(x, 11, 0))
            try s.startSleep(at: at(x, 13, 0), by: .mor, now: at(x, 13, 10))
            try s.stopSleep(at: at(x, 14, 20 + i % 4 * 5), nap: true, now: at(x, 14, 40))
            guard i > 1 else { continue }
            try s.startSleep(at: at(x, 19, 0), by: .far, now: at(x, 19, 10))
            try s.stopSleep(at: at(plusDays(x, 1), 6, 15), nap: false, now: at(plusDays(x, 1), 6, 30))
        }
        func same(_ now: Date) {
            let h = s.sleepInput(now: now)
            #expect(s.prediction(h, now: now) == s.prediction(now: now))
            #expect(s.basicPrediction(h, now: now) == s.basicPrediction(now: now))
            #expect(s.dayPlan(h, now: now) == s.dayPlan(now: now))
            #expect(s.awakeSince(h, now: now) == s.awakeSince(now: now))
            #expect(s.todaySleeps(h, now: now) == s.todaySleeps(now: now).compactMap(\.sample))
            let m = s.missingNight(h, now: now), m2 = s.missingNight(now: now)
            #expect(m?.start == m2?.start && m?.end == m2?.end)
        }
        same(at(d, 7, 0))
        #expect(s.missingNight(now: at(d, 7, 0)) != nil) // natten til i dag mangler
        same(at(d, 8, 0))
        try s.startSleep(at: at(d, 9, 35), by: .mor, now: at(d, 9, 40))
        same(at(d, 10, 0)) // under en lur: planen regnes fra forventet opvågning
        #expect(s.sleepInput(now: at(d, 10, 0)).running != nil)
        try s.stopSleep(at: at(d, 10, 45), nap: true, now: at(d, 11, 0))
        same(at(d, 11, 0))
        same(at(d, 16, 0))
    }

    @Test func barnetSlåsOpÉnGang() throws {
        let s = try store()
        let a = try s.createChild(name: "Folke", birthDate: day(2026, 2, 1))
        let b = try s.createChild(name: "Ida", birthDate: day(2024, 1, 1))
        s.currentChildID = a.id
        s.withChild {
            #expect(s.child() == a)
            // Skiftes barnet undervejs (tvillinger, notifikationer), gælder det nye
            s.currentChildID = b.id
            #expect(s.child() == b)
            #expect(s.sleepInput().childID == b.id)
            s.currentChildID = a.id
            #expect(s.child() == a)
        }
        s.currentChildID = nil
        #expect(s.child() == a) // det først oprettede
    }
}
