import Foundation
import Testing
@testable import FolkeCore

@Suite("Folke Plus") struct PlusTests {
    let start = at(day(2026, 6, 1), 22, 30)

    @Test func proevenVarer14HeleDage() {
        #expect(Plus.status(purchased: false, trialStart: start, now: at(day(2026, 6, 1), 23, 0), calendar: cph) == .trial(daysLeft: 14))
        #expect(Plus.status(purchased: false, trialStart: start, now: at(day(2026, 6, 14), 23, 59), calendar: cph) == .trial(daysLeft: 1))
        #expect(Plus.status(purchased: false, trialStart: start, now: at(day(2026, 6, 15), 0, 0), calendar: cph) == .locked)
    }

    @Test func koebSlaarAltidIgennem() {
        #expect(Plus.status(purchased: true, trialStart: start, now: day(2027, 1, 1), calendar: cph) == .purchased)
        #expect(Plus.Status.purchased.unlocked && !Plus.Status.locked.unlocked && Plus.Status.trial(daysLeft: 3).unlocked)
    }

    @Test func udenStartErProevenFuld() {
        #expect(Plus.status(purchased: false, trialStart: nil) == .trial(daysLeft: 14))
    }

    @Test func tekster() {
        #expect(Plus.Status.trial(daysLeft: 1).text == "Prøveperiode: 1 dag tilbage")
        #expect(Plus.Status.trial(daysLeft: 9).text == "Prøveperiode: 9 dage tilbage")
    }
}
