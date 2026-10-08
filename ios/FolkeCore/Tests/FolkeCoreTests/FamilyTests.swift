import CoreData
import Foundation
import Testing
@testable import FolkeCore

/// Flere børn: familien, opgradering fra version 1, valgt barn og forslaget om at skjule forudsigelsen.
@MainActor @Suite("Familie og flere børn", .serialized) struct FamilyTests {
    let d = day(2026, 6, 10)

    @Test func opgraderingFraVersion1FlytterUdpumpningOgTavlenTilFamilien() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "folke-v1-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // En database som før familien (version 1), med data
        let old = NSPersistentContainer(name: "Folke", managedObjectModel: FolkeModel.build(version: 1))
        let desc = NSPersistentStoreDescription(url: dir.appending(path: "Folke.sqlite"))
        desc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        old.persistentStoreDescriptions = [desc]
        var loadError: Error?
        old.loadPersistentStores { _, e in loadError = e }
        try #require(loadError == nil)
        let ctx = old.viewContext
        func new(_ name: String, _ values: [String: Any]) -> NSManagedObject {
            let o = NSEntityDescription.insertNewObject(forEntityName: name, into: ctx)
            for (k, v) in values { o.setValue(v, forKey: k) }
            return o
        }
        let child = new("Child", ["id": UUID(), "name": "Folke", "birthDate": day(2026, 2, 1), "createdAt": d])
        new("Settings", ["id": UUID(), "createdAt": d, "featurePump": false, "pumpRemindHours": 2.0, "child": child])
        new("Sleep", ["id": UUID(), "start": at(d, 12, 0), "end": at(d, 13, 0), "nap": true, "child": child])
        new("Pumping", ["id": UUID(), "time": at(d, 9, 0), "amountMl": 120.0, "child": child])
        new("Stroke", ["id": UUID(), "color": "#f4f1ea", "width": 0.012, "createdAt": d, "child": child])
        try ctx.save()
        for s in old.persistentStoreCoordinator.persistentStores { try old.persistentStoreCoordinator.remove(s) }

        // Åbnes med den nye model
        let s = try FolkeStore(directory: dir)
        s.calendar = cph
        let fam = try #require(s.family())
        #expect(s.child()?.family == fam && s.child()?.name == "Folke")
        #expect(!fam.featurePump && fam.pumpRemindHours == 2)
        #expect(s.pumpings(since: .distantPast).map(\.amountMl) == [120])
        #expect(s.strokes().count == 1)
        #expect(s.sleeps(since: .distantPast).count == 1)
        #expect(s.settings()?.featurePrediction == true)

        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "Folke-opgradering.sqlite").path))

        // Åbnes igen: ingen ny opgradering og ingen ekstra familie
        let again = try FolkeStore(directory: dir)
        #expect(again.fetch(Family.self).count == 1)
    }

    @Test func toBoernHarHverSinSoevnMenFaellesUdpumpning() throws {
        let s = try FolkeStore(inMemory: true)
        s.calendar = cph
        let folke = try s.createChild(name: "Folke", birthDate: day(2026, 2, 1))
        try s.startSleep(by: .mor, now: at(d, 12, 0))
        try s.stopSleep(now: at(d, 13, 0))
        try s.addPumping(amountMl: 100, at: at(d, 9, 0), now: at(d, 14, 0))
        try s.addFeeding(.left, at: at(d, 10, 0), now: at(d, 14, 0))

        let ida = try s.createChild(name: "Ida", birthDate: day(2024, 5, 1), sex: .girl, now: at(d, 14, 0))
        #expect(s.child() == ida && s.children() == [ida, folke]) // ældste først
        #expect(s.sleeps(since: .distantPast).isEmpty && s.todayFeedings(now: at(d, 14, 0)).isEmpty)
        #expect(s.pumpings(since: .distantPast).count == 1) // familiens
        #expect(s.settings()?.child == ida)
        #expect(s.settings()?.featureSolids == true && s.settings()?.featureBreast == false) // 2 år: startvalg efter alder

        // Begge kan sove på samme tid
        try s.startSleep(by: .far, now: at(d, 13, 30))
        s.currentChildID = folke.id
        try s.startSleep(by: .mor, now: at(d, 13, 40))
        #expect(s.runningSleep()?.start == at(d, 13, 40))
        s.currentChildID = ida.id
        #expect(s.runningSleep()?.start == at(d, 13, 30))

        // Slet Ida: hendes søvn forsvinder, udpumpningen bliver
        try s.deleteChild(ida)
        #expect(s.child() == folke && s.children() == [folke])
        #expect(s.fetch(Sleep.self).allSatisfy { $0.child == folke })
        #expect(s.pumpings(since: .distantPast).count == 1)
        #expect(s.family()?.children?.count == 1)
    }

    @Test func forudsigelsenKanSkjulesNaarLurenErVaek() throws {
        let s = try FolkeStore(inMemory: true)
        s.calendar = cph
        try s.createChild(name: "Folke", birthDate: day(2023, 11, 1)) // 31 mdr. den 10. juni 2026
        for i in 1...14 {
            let night = plusDays(d, -i)
            try s.startSleep(by: .mor, now: at(night, 19, 30))
            try s.stopSleep(nap: false, now: at(plusDays(night, 1), 6, 30))
        }
        let now = at(d, 12, 0)
        #expect(s.prediction(now: now) != nil)
        let sug = try #require(s.suggestions(now: now).first { $0.id == .hidePrediction })
        #expect(sug.text.hasPrefix("Han har ikke sovet lur i 2 uger"))
        try s.answer(.hidePrediction, .yes, now: now)
        #expect(s.prediction(now: now) == nil && s.basicPrediction(now: now) == nil && s.dayPlan(now: now) == nil)
        try s.setFeature(.prediction, true)
        #expect(s.prediction(now: now) != nil)
    }

    @Test func ingenForslagFoer2HalvtAarEllerMedLure() throws {
        let s = try FolkeStore(inMemory: true)
        s.calendar = cph
        try s.createChild(name: "Folke", birthDate: day(2024, 6, 1)) // 24 mdr.
        try s.startSleep(by: .mor, now: at(plusDays(d, -1), 19, 30))
        try s.stopSleep(nap: false, now: at(d, 6, 30))
        #expect(!s.suggestions(now: at(d, 12, 0)).contains { $0.id == .hidePrediction })
    }
}
