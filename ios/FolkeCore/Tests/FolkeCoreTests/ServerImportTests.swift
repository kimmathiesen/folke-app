import Foundation
import Testing
@testable import FolkeCore

/// Skjult import fra Folke-serverens eksport (PLAN.md afsnit 8).
@MainActor @Suite("Import fra server", .serialized) struct ServerImportTests {
    let json = """
    {"child": [{"id": 1, "bb_id": 1, "first_name": "Folke", "birth_date": "2026-06-20"}],
     "sleep": [{"id": 1, "bb_id": 28, "child": 1, "start": "2026-10-04T15:44:51+00:00", "end": "2026-10-04T17:22:01+00:00", "nap": 1},
               {"id": 2, "bb_id": null, "child": 1, "start": "2026-10-04T18:15:00+00:00", "end": "2026-10-05T05:50:00+00:00", "nap": 0}],
     "timer": [{"id": 1, "bb_id": null, "child": 1, "name": "Søvn", "start": "2026-10-06T09:33:29+00:00"}],
     "feeding": [{"id": 1, "bb_id": 1, "child": 1, "start": "2026-10-04T18:14:00+00:00", "end": "2026-10-04T18:14:00+00:00", "type": "formula", "method": "bottle", "amount": 30.0, "notes": null},
                 {"id": 2, "bb_id": null, "child": 1, "start": "2026-10-05T08:00:00+00:00", "end": "2026-10-05T08:00:00+00:00", "type": "breast milk", "method": "left breast", "amount": null, "notes": null},
                 {"id": 3, "bb_id": null, "child": 1, "start": "2026-10-05T11:00:00+00:00", "end": "2026-10-05T11:00:00+00:00", "type": "solid food", "method": "parent fed", "amount": null, "notes": "grød"}],
     "pumping": [{"id": 1, "bb_id": 2, "child": 1, "start": "2026-10-03T15:23:17+00:00", "end": "2026-10-03T15:23:17+00:00", "amount": 40.0, "notes": "", "side": "both", "minutes": 15.0}],
     "growth": [{"id": 1, "date": "2026-09-01", "w": 6.1, "l": 61.0, "h": null}],
     "night_wake": [{"id": 1, "child": 1, "start": "2026-10-04T23:10:00+00:00", "end": "2026-10-04T23:30:00+00:00"}],
     "prefs": {"features": {"breast": true, "solids": true, "pump": false}, "sug": {}, "sex": "boy", "pump_remind": 2.5, "child_name": ""}}
    """

    @Test func foersteImportOpretterBarnOgIndstillinger() throws {
        let s = try FolkeStore(inMemory: true)
        let r = try s.importServerExport(Data(json.utf8))
        #expect(r == ServerImportResult(sleeps: 2, feedings: 3, pumpings: 1, growth: 1, wakes: 1, createdChild: true, runningSleep: true))
        #expect(s.wakes(from: .distantPast).first?.minutes() == 20)
        #expect(s.child()?.name == "Folke" && s.child()?.sex == "boy")
        let set = try #require(s.settings())
        let fam = try #require(s.family())
        #expect(set.featureSolids && !fam.featurePump && fam.pumpRemindHours == 2.5)
        #expect(s.runningSleep()?.start == FolkeStore.time("2026-10-06T09:33:29+00:00"))
        let sleeps = s.sleeps(since: .distantPast)
        #expect(sleeps.map(\.nap) == [true, false])
        let feeds = s.fetch(Feeding.self).sorted { $0.serverID < $1.serverID }
        #expect(feeds.map(\.kind) == ["bottle", "left", "solid"])
        #expect(feeds[0].milk == "formula" && feeds[0].amountMl == 30 && feeds[2].note == "grød")
        #expect(s.pumpings(since: .distantPast).first?.side == "both")
        #expect(s.growthPoints().first?.values[.length] == 61)
    }

    @Test func gentagetImportGiverIngenDubletter() throws {
        let s = try FolkeStore(inMemory: true)
        try s.importServerExport(Data(json.utf8))
        try s.stopSleep() // den importerede timer stoppes i appen
        let r = try s.importServerExport(Data(json.utf8))
        #expect(!r.createdChild && !r.runningSleep)
        #expect(s.fetch(Sleep.self).count == 3) // 2 fra serveren + den stoppede timer
        #expect(s.fetch(Feeding.self).count == 3 && s.fetch(Pumping.self).count == 1 && s.fetch(Growth.self).count == 1)
        #expect(s.fetch(NightWake.self).count == 1) // opvågningen genkendes på starttidspunktet
    }

    @Test func eksisterendeBarnBevaresOgAppensDataRoeresIkke() throws {
        let s = try FolkeStore(inMemory: true)
        try s.createChild(name: "Ida", birthDate: day(2026, 6, 20), sex: .girl)
        try s.addPumping(amountMl: 100)
        try s.importServerExport(Data(json.utf8))
        #expect(s.child()?.name == "Ida" && s.child()?.sex == "girl")
        #expect(s.fetch(Pumping.self).count == 2)
    }

    @Test func forkertFilAfvises() throws {
        let s = try FolkeStore(inMemory: true)
        #expect(throws: ServerImportError.self) { try s.importServerExport(Data("{\"x\": 1}".utf8)) }
        #expect(throws: ServerImportError.self) { try s.importServerExport(Data("{\"child\": []}".utf8)) }
    }

    // MARK: Spejling (midlertidig synkronisering)

    @Test func spejlingFjernerDetServerenHarSlettet() throws {
        let s = try FolkeStore(inMemory: true)
        try s.mirrorServerExport(Data(json.utf8))
        #expect(s.runningSleep() != nil)
        // Timeren er stoppet på serveren (ny søvn id 3), måltid 3, udpumpningen, målingen og opvågningen er slettet
        let next = json
            .replacingOccurrences(of: #""timer": [{"id": 1, "bb_id": null, "child": 1, "name": "Søvn", "start": "2026-10-06T09:33:29+00:00"}]"#,
                                  with: #""timer": []"#)
            .replacingOccurrences(of: #""nap": 0}],"#,
                                  with: #""nap": 0}, {"id": 3, "child": 1, "start": "2026-10-06T09:33:29+00:00", "end": "2026-10-06T10:40:00+00:00", "nap": 1}],"#)
            .replacingOccurrences(of: #",\s*\{"id": 3, "bb_id": null[^}]*\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #""growth": [{"id": 1, "date": "2026-09-01", "w": 6.1, "l": 61.0, "h": null}]"#, with: #""growth": []"#)
            .replacingOccurrences(of: #""night_wake": [{"id": 1, "child": 1, "start": "2026-10-04T23:10:00+00:00", "end": "2026-10-04T23:30:00+00:00"}]"#,
                                  with: #""night_wake": []"#)
        try s.mirrorServerExport(Data(next.utf8))
        #expect(s.runningSleep() == nil)
        #expect(s.fetch(Sleep.self).map(\.serverID).sorted() == [1, 2, 3])
        #expect(s.fetch(Feeding.self).map(\.serverID).sorted() == [1, 2])
        #expect(s.fetch(Pumping.self).count == 1)
        #expect(s.fetch(Growth.self).isEmpty && s.wakes(from: .distantPast).isEmpty)
    }

    @Test func spejlingRoererIkkeLokaleRaekkerOgDeleteLocalOnlyRydder() throws {
        let s = try FolkeStore(inMemory: true)
        try s.mirrorServerExport(Data(json.utf8))
        try s.addPumping(amountMl: 90) // kun på enheden (serverID 0)
        try s.mirrorServerExport(Data(json.utf8))
        #expect(s.fetch(Pumping.self).count == 2)
        try s.deleteLocalOnly()
        #expect(s.fetch(Pumping.self).map(\.serverID) == [1])
        #expect(s.wakes(from: .distantPast).isEmpty) // opvågninger hentes igen ved næste spejling
        try s.mirrorServerExport(Data(json.utf8))
        #expect(s.wakes(from: .distantPast).count == 1)
    }

    @Test func serverensIdForEnOpvaagning() throws {
        let start = try #require(FolkeStore.time("2026-10-04T23:10:00+00:00"))
        #expect(FolkeStore.serverWakeID(Data(json.utf8), start: start) == 1)
        #expect(FolkeStore.serverWakeID(Data(json.utf8), start: .now) == nil)
    }

    @Test func spejlingFoelgerServerensTimerSelvMedGenbrugtNummer() throws {
        let s = try FolkeStore(inMemory: true)
        try s.mirrorServerExport(Data(json.utf8))
        #expect(s.runningSleep()?.start == FolkeStore.time("2026-10-06T09:33:29+00:00"))
        // Serveren genbruger timer-id 1 til en ny søvn, og appen har ikke hentet imellem
        let later = json.replacingOccurrences(of: "2026-10-06T09:33:29+00:00", with: "2026-10-06T18:39:50+00:00")
        try s.mirrorServerExport(Data(later.utf8))
        #expect(s.runningSleep()?.start == FolkeStore.time("2026-10-06T18:39:50+00:00"))
        // Den kørende søvn er stoppet på enheden (fx fra låseskærmen), men kører stadig på serveren
        try s.stopSleep()
        try s.mirrorServerExport(Data(later.utf8))
        #expect(s.runningSleep()?.start == FolkeStore.time("2026-10-06T18:39:50+00:00"))
        #expect(s.fetch(Sleep.self).filter { $0.serverID < 0 }.count == 1)
    }
}
