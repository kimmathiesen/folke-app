import AppIntents
import FolkeCore
import Foundation
import UserNotifications
import WidgetKit

/// Fælles efter enhver ændring fra en App Intent: notifikationer, widgets, Live Activity og appen.
@MainActor enum FolkeSync {
    static func afterChange(_ store: FolkeStore) async {
        store.context.refreshAllObjects()
        await Notifier.reschedule(store: store)
        let running = store.runningSleep()
        let plan = store.dayPlan()
        await SleepLiveActivity.sync(running: running.flatMap { r in r.start.map { ($0, r.nap) } },
                               name: store.child()?.name ?? "", expectedWake: plan?.wake)
        WidgetCenter.shared.reloadAllTimelines()
        NotificationCenter.default.post(name: FolkeShared.changed, object: nil)
    }
}

extension FolkeShared {
    /// Widgets, Live Activity og Siri er med i Folke Plus.
    static func requirePlus() throws {
        guard plus().unlocked else { throw IntentFailure(message: Plus.Feature.extensions.lockedText) }
    }
}

struct IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    var message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

/// Start søvn (Siri, Genveje og knappen i widgetten). Kører i appen, så Live Activity kan startes.
struct StartSleepIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start søvn"
    static let description = IntentDescription("Starter en søvn nu. Lur eller nat gættes ud fra klokken.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try FolkeShared.requirePlus()
        let store = FolkeShared.store
        guard let child = store.child() else { throw IntentFailure(message: "Åbn Folke og opret barnet først") }
        let name = child.name ?? "Babyen"
        if store.runningSleep() != nil {
            return .result(dialog: "\(name) sover allerede")
        }
        let s = try store.startSleep(by: FolkeShared.role)
        await FolkeSync.afterChange(store)
        return .result(dialog: "\(s.nap ? "Lur" : "Nat") startet kl. \(Format.time(s.start ?? .now))")
    }
}

/// Stop den kørende søvn. Lur eller nat gættes ud fra start og længde.
struct StopSleepIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop søvn"
    static let description = IntentDescription("Stopper den søvn, der er i gang.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try FolkeShared.requirePlus()
        let store = FolkeShared.store
        guard let running = store.runningSleep(), let start = running.start else {
            return .result(dialog: "Der er ingen søvn i gang")
        }
        try store.stopSleep()
        await FolkeSync.afterChange(store)
        let mins = max(0, Int(Date.now.timeIntervalSince(start) / 60))
        return .result(dialog: "Søvn stoppet efter \(Format.duration(minutes: mins))")
    }
}

/// Log en udpumpning med Siri: «Log udpumpning i Folke».
struct LogPumpingIntent: AppIntent {
    static let title: LocalizedStringResource = "Log udpumpning"
    static let description = IntentDescription("Gemmer en udpumpning nu.")

    @Parameter(title: "Mængde (ml)", inclusiveRange: (1, 1000))
    var ml: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try FolkeShared.requirePlus()
        let store = FolkeShared.store
        guard store.child() != nil else { throw IntentFailure(message: "Åbn Folke og opret barnet først") }
        do {
            try store.addPumping(amountMl: Double(ml))
        } catch {
            throw IntentFailure(message: (error as? LocalizedError)?.errorDescription ?? "Kunne ikke gemme")
        }
        await FolkeSync.afterChange(store)
        return .result(dialog: "Udpumpning på \(ml) ml er gemt")
    }
}

/// Log en flaske med Siri: «Log flaske i Folke».
struct LogBottleIntent: AppIntent {
    static let title: LocalizedStringResource = "Log flaske"
    static let description = IntentDescription("Gemmer en flaske nu.")

    @Parameter(title: "Mængde (ml)", inclusiveRange: (1, 500))
    var ml: Int

    @Parameter(title: "Erstatning", default: false)
    var formula: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try FolkeShared.requirePlus()
        let store = FolkeShared.store
        guard store.child() != nil else { throw IntentFailure(message: "Åbn Folke og opret barnet først") }
        do {
            try store.addFeeding(.bottle, amountMl: Double(ml), milk: formula ? .formula : .breast)
        } catch {
            throw IntentFailure(message: (error as? LocalizedError)?.errorDescription ?? "Kunne ikke gemme")
        }
        await FolkeSync.afterChange(store)
        return .result(dialog: "Flaske på \(ml) ml er gemt")
    }
}
