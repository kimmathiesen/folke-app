import Foundation
import Testing
@testable import FolkeCore

/// Opvågninger om natten (som test_app.py i webappen).
@MainActor @Suite("Opvågninger om natten", .serialized) struct NightWakeTests {
    let d = day(2026, 6, 10)

    func store() throws -> FolkeStore {
        let s = try FolkeStore(inMemory: true)
        s.calendar = cph
        try s.createChild(name: "Folke", birthDate: day(2026, 2, 1), now: d)
        return s
    }

    @Test func vaagnedeOgSoverIgen() throws {
        let s = try store()
        try s.startWake(by: .mor, now: at(d, 23, 0)) // ingen søvn i gang: intet sker
        #expect(s.wakes(from: .distantPast).isEmpty)
        try s.startSleep(by: .mor, now: at(d, 19, 30))
        try s.startWake(by: .mor, now: at(d, 23, 0))
        try s.startWake(by: .far, now: at(d, 23, 5)) // to tryk giver ikke to opvågninger
        try s.stopWake(now: at(d, 23, 25))
        let w = s.wakes(from: at(d, 19, 30))
        #expect(w.count == 1 && w[0].end == at(d, 23, 25) && w[0].minutes() == 25)
        try s.stopSleep(nap: false, now: at(plusDays(d, 1), 6, 30))
        #expect(s.sleeps(since: .distantPast).first?.end == at(plusDays(d, 1), 6, 30))
    }

    @Test func stopMensHanErVaagenSlutterNattenVedOpvaagningen() throws {
        let s = try store()
        try s.startSleep(by: .mor, now: at(d, 19, 30))
        try s.startWake(by: .mor, now: at(plusDays(d, 1), 5, 40))
        try s.stopSleep(nap: false, now: at(plusDays(d, 1), 6, 15))
        #expect(s.sleeps(since: .distantPast).first?.end == at(plusDays(d, 1), 5, 40))
        #expect(s.wakes(from: .distantPast).isEmpty && s.openWake() == nil)
    }

    @Test func sletNatSletterOpvaagninger() throws {
        let s = try store()
        try s.startSleep(by: .mor, now: at(d, 19, 30))
        try s.startWake(by: .mor, now: at(d, 23, 0))
        try s.stopWake(now: at(d, 23, 20))
        try s.stopSleep(nap: false, now: at(plusDays(d, 1), 6, 30))
        try s.deleteSleep(try #require(s.sleeps(since: .distantPast).first))
        #expect(s.wakes(from: .distantPast).isEmpty)
    }
}
