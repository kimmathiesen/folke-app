import Foundation
import Testing
@testable import FolkeCore

@MainActor @Suite("Tvillinger", .serialized) struct TwinTests {
    let d = day(2026, 6, 10)

    func family() throws -> (FolkeStore, Child, Child, Child) {
        let s = try FolkeStore(inMemory: true)
        s.calendar = cph
        let ida = try s.createChild(name: "Ida", birthDate: day(2024, 1, 5), sex: .girl, now: d)
        let alma = try s.createChild(name: "Alma", birthDate: at(day(2026, 2, 1), 3, 10), sex: .girl, now: d)
        let bo = try s.createChild(name: "Bo", birthDate: at(day(2026, 2, 1), 3, 40), now: d)
        return (s, ida, alma, bo)
    }

    @Test func tvillingerHarSammeFoedselsdato() throws {
        let (s, ida, alma, bo) = try family()
        s.currentChildID = alma.id
        #expect(s.twins() == [bo])
        s.currentChildID = ida.id
        #expect(s.twins().isEmpty) // storesøster er ikke tvilling
    }

    @Test func startOgStopBegge() throws {
        let (s, ida, alma, bo) = try family()
        s.currentChildID = bo.id
        try s.startSleep(by: .mor, now: at(d, 12, 0)) // Bo faldt i søvn først
        s.currentChildID = alma.id
        try s.startSleepWithTwins(by: .far, now: at(d, 12, 20))
        #expect(s.runningSleep()?.start == at(d, 12, 20))
        #expect(s.twinsSleepingSince().map(\.since) == [at(d, 12, 0)]) // Bo's start er urørt
        #expect(s.child() == alma) // det valgte barn er det samme bagefter

        try s.stopSleepWithTwins(now: at(d, 13, 30))
        #expect(s.runningSleep() == nil && s.twinsSleepingSince().map(\.since) == [nil])
        s.currentChildID = bo.id
        #expect(s.sleeps(since: .distantPast).map(\.nap) == [true]) // gættet som lur
        s.currentChildID = ida.id
        #expect(s.sleeps(since: .distantPast).isEmpty && s.runningSleep() == nil) // storesøster er urørt
    }
}
