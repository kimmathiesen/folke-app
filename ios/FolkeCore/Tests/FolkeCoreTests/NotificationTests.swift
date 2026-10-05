import Foundation
import Testing
@testable import FolkeCore

/// Reglerne for lokale notifikationer (ios/PLAN.md afsnit 4, napper.main og pump_reminder i app.py).
@Suite("Notifikationer") struct NotificationTests {
    let planner = NotificationPlanner(calendar: cph)
    let d = day(2026, 6, 10)

    func pred(_ kind: Prediction.Kind = .nap, at h: Int, _ m: Int, last: Int = 1) -> Prediction {
        Prediction(kind: kind, time: at(d, h, m), windowMin: 150, source: .position(1), lastID: id(last))
    }

    func input(_ now: Date, _ p: Prediction?, sleeping: Bool = false, name: String = "Folke",
               enabled: Set<NotificationKind> = NotificationKind.defaultsOn) -> NotificationPlanner.Input {
        .init(now: now, prediction: p, sleeping: sleeping, childName: name, enabled: enabled)
    }

    @Test func planlaeggerFoerOgEfter() {
        let (n, _) = planner.plan(input(at(d, 12, 0), pred(at: 13, 40)), log: .init())
        #expect(n.count == 2)
        let soon = n.first { $0.kind == .sleepSoon }!
        #expect(soon.fireDate == at(d, 13, 10))
        #expect(soon.title == "Søvn")
        #expect(soon.body == "Tid til at slappe af. Næste lur ca. kl. 13:40")
        let late = n.first { $0.kind == .overdue }!
        #expect(late.fireDate == at(d, 13, 55))
        #expect(late.body == "Folke virker meget frisk. Prøv alligevel en lur")
    }

    @Test func sengetidOgUdenNavn() {
        let (n, _) = planner.plan(input(at(d, 17, 0), pred(.bedtime, at: 19, 30), name: ""), log: .init())
        #expect(n.first { $0.kind == .sleepSoon }!.body == "Tid til at slappe af. Sengetid ca. kl. 19:30")
        #expect(n.first { $0.kind == .overdue }!.body == "Babyen virker meget frisk. Prøv alligevel at putte til natten")
    }

    @Test func ingentingNaarSoevnKoerer() {
        let (n, _) = planner.plan(input(at(d, 12, 0), pred(at: 13, 40), sleeping: true), log: .init())
        #expect(n.isEmpty)
    }

    @Test func kunSlaaetTilPaaEnheden() {
        let (n, _) = planner.plan(input(at(d, 12, 0), pred(at: 13, 40), enabled: [.overdue]), log: .init())
        #expect(n.map(\.kind) == [.overdue])
    }

    @Test func inden30MinSendesMedDetSamme() {
        let now = at(d, 13, 20)
        let (n, _) = planner.plan(input(now, pred(at: 13, 40)), log: .init())
        #expect(n.first { $0.kind == .sleepSoon }!.fireDate == now)
    }

    @Test func hoejstEnGangPrForudsigelse() {
        let p = pred(at: 13, 40)
        let (_, log) = planner.plan(input(at(d, 12, 0), p), log: .init())
        // Appen åbnes igen, efter «slap af» er sendt: den sendes ikke igen, men «virker frisk» ligger stadig klar
        let (n, _) = planner.plan(input(at(d, 13, 20), p), log: log)
        #expect(n.map(\.kind) == [.overdue])
        // En ny forudsigelse (ny sidste søvn) giver nye beskeder
        let (n2, _) = planner.plan(input(at(d, 15, 0), pred(at: 17, 0, last: 2)), log: log)
        #expect(n2.count == 2)
    }

    @Test func nyPlanFoerTidErstatterDenGamle() {
        let (_, log) = planner.plan(input(at(d, 12, 0), pred(at: 13, 40)), log: .init())
        // Samme sidste søvn, men tiden er flyttet (fx efter rettelse), inden beskeden er sendt
        let (n, _) = planner.plan(input(at(d, 12, 30), pred(at: 14, 0)), log: log)
        #expect(n.first { $0.kind == .sleepSoon }!.fireDate == at(d, 13, 30))
    }

    @Test func overdueHoejst2TimerForSent() {
        let p = pred(at: 13, 40)
        #expect(planner.plan(input(at(d, 15, 40), p), log: .init()).notifications.map(\.kind) == [.overdue])
        #expect(planner.plan(input(at(d, 15, 41), p), log: .init()).notifications.isEmpty)
    }

    @Test func udpumpningEfterXTimer() {
        var i = input(at(d, 9, 30), nil, enabled: [.pump])
        i.pumpFeature = true
        i.pumpRemindHours = 3
        i.lastPump = (id(7), at(d, 9, 15))
        let (n, log) = planner.plan(i, log: .init())
        #expect(n == [PlannedNotification(kind: .pump, fireDate: at(d, 12, 15), title: "Udpumpning",
                                          body: "Det er 3 timer siden sidste udpumpning (kl. 09:15)")])
        // Højst én gang pr. udpumpning
        i.now = at(d, 13, 0)
        #expect(planner.plan(i, log: log).notifications.isEmpty)
    }

    @Test func udpumpningIkkeOmNatten() {
        var i = input(at(d, 20, 0), nil, enabled: [.pump])
        i.pumpFeature = true
        i.pumpRemindHours = 3
        i.lastPump = (id(7), at(d, 20, 0))
        let n = planner.plan(i, log: .init()).notifications
        #expect(n.first?.fireDate == at(plusDays(d, 1), 7, 0))
        #expect(n.first?.body == "Det er 11 timer siden sidste udpumpning (kl. 20:00)")
    }

    @Test func forsinketUdpumpningVenterTilMorgenen() {
        // Appen åbnes kl. 22:38, og påmindelsen skulle have været sendt kl. 16:40
        var i = input(at(d, 22, 38), nil, enabled: [.pump])
        i.pumpFeature = true
        i.pumpRemindHours = 3
        i.lastPump = (id(7), at(d, 13, 40))
        let n = planner.plan(i, log: .init()).notifications
        #expect(n.first?.fireDate == at(plusDays(d, 1), 7, 0))
        #expect(n.first?.body == "Det er 17 timer siden sidste udpumpning (kl. 13:40)")
        // Om dagen sendes en forsinket påmindelse med det samme
        i.now = at(d, 18, 0)
        #expect(planner.plan(i, log: .init()).notifications.first?.fireDate == at(d, 18, 0))
        #expect(planner.plan(i, log: .init()).notifications.first?.body == "Det er 4 timer siden sidste udpumpning (kl. 13:40)")
    }

    @Test func udpumpningFraSomStandard() {
        var i = input(at(d, 9, 30), nil)
        i.pumpFeature = true
        i.lastPump = (id(7), at(d, 9, 15))
        #expect(planner.plan(i, log: .init()).notifications.isEmpty)
        i.enabled = [.pump]
        i.pumpFeature = false
        #expect(planner.plan(i, log: .init()).notifications.isEmpty)
    }

    @Test func stilletid() {
        #expect(planner.outsideQuiet(at(d, 21, 59)) == at(d, 21, 59))
        #expect(planner.outsideQuiet(at(d, 22, 0)) == at(plusDays(d, 1), 7, 0))
        #expect(planner.outsideQuiet(at(d, 3, 0)) == at(d, 7, 0))
        #expect(planner.outsideQuiet(at(d, 7, 0)) == at(d, 7, 0))
    }
}
