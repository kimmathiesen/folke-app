import FolkeCore
import Observation
import OSLog
import UserNotifications

/// Lokale notifikationer (ios/PLAN.md afsnit 4). Reglerne ligger i `NotificationPlanner` i FolkeCore.
/// Planlægges forfra, hver gang forsiden opdateres (lokale ændringer, iCloud, appen åbnes, hvert minut).
/// Hvilke beskedtyper denne enhed vil have, og hvad der er sendt, gemmes kun på enheden (i App Group, så App Intents
/// fra Siri og widgets kan planlægge med `Notifier.reschedule(store:)` uden appens skærm).
@MainActor @Observable
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    enum Status { case unknown, notAsked, allowed, denied }

    private(set) var status: Status = .unknown
    private let center = UNUserNotificationCenter.current()
    private var lastPlan: [PlannedNotification]?
    private static let logger = Logger(subsystem: "dk.folkeapp.folke", category: "notifikationer")
    private static var defaults: UserDefaults { FolkeShared.defaults }

    /// Beskedtyper til og fra på denne enhed (standard: søvn til, udpumpning fra).
    private(set) var enabled: Set<NotificationKind>

    override init() {
        enabled = Self.enabledKinds
        super.init()
        center.delegate = self
        Task { await refreshStatus() }
    }

    func refreshStatus() async {
        let s = await center.notificationSettings()
        status = switch s.authorizationStatus {
        case .notDetermined: .notAsked
        case .denied: .denied
        default: .allowed
        }
    }

    /// Bed om lov (fra et tryk, som i webappen). Giver false, hvis brugeren siger nej.
    func requestPermission() async -> Bool {
        let ok = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshStatus()
        lastPlan = nil
        return ok
    }

    func setEnabled(_ kind: NotificationKind, _ on: Bool) {
        if on { enabled.insert(kind) } else { enabled.remove(kind) }
        Self.defaults.set(enabled.map(\.rawValue).sorted(), forKey: "folke.kinds")
        lastPlan = nil
    }

    func sendTest() {
        let c = UNMutableNotificationContent()
        c.title = "Folke"
        c.body = "Notifikationer virker på denne enhed."
        c.sound = .default
        center.add(UNNotificationRequest(identifier: "test", content: c,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }

    /// Beskedtyper til og fra på denne enhed (standard: søvn til, udpumpning fra).
    static var enabledKinds: Set<NotificationKind> {
        (defaults.stringArray(forKey: "folke.kinds") ?? UserDefaults.standard.stringArray(forKey: "folke.kinds"))?
            .compactMap(NotificationKind.init(rawValue:)).reduce(into: Set()) { $0.insert($1) } ?? NotificationKind.defaultsOn
    }

    static var log: NotificationLog {
        get {
            defaults.data(forKey: "folke.notificationLog")
                .flatMap { try? JSONDecoder().decode(NotificationLog.self, from: $0) } ?? NotificationLog()
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "folke.notificationLog") }
    }

    /// Planlæg forfra (fra appens skærm). Gentages kun, hvis planen har ændret sig.
    func reschedule(_ input: NotificationPlanner.Input) {
        guard status == .allowed else { return }
        var input = input
        input.enabled = enabled
        let plan = Self.plan(input)
        if plan == lastPlan { return }
        lastPlan = plan
        Self.apply(plan)
    }

    /// Planlæg forfra uden appens skærm (App Intents fra Siri, widgets og Live Activity).
    static func reschedule(store: FolkeStore, now: Date = .now) async {
        guard await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized else { return }
        let s = store.settings()
        // Uden Folke Plus regnes beskederne ud fra den enkle forudsigelse (som appens forside)
        let prediction = FolkeShared.plus(now: now).unlocked ? store.prediction(now: now) : store.basicPrediction(now: now)
        var input = NotificationPlanner.Input(now: now, prediction: prediction,
                                              sleeping: store.runningSleep() != nil, childName: store.child()?.name ?? "",
                                              enabled: enabledKinds, pumpFeature: s?.featurePump ?? false,
                                              pumpRemindHours: s?.pumpRemindHours ?? 3, lastPump: store.lastPumping(now: now))
        input.enabled = enabledKinds
        apply(plan(input))
    }

    private static func plan(_ input: NotificationPlanner.Input) -> [PlannedNotification] {
        let (plan, newLog) = NotificationPlanner().plan(input, log: log)
        log = newLog
        return plan
    }

    /// Fast id pr. type, så en ny plan erstatter den gamle. Typer uden plan fjernes.
    private static func apply(_ plan: [PlannedNotification]) {
        let center = UNUserNotificationCenter.current()
        let ids = NotificationKind.allCases.map(\.rawValue)
        let removed = ids.filter { id in !plan.contains { $0.id == id } }
        center.removePendingNotificationRequests(withIdentifiers: removed)
        logger.info("Fjernet: \(removed.joined(separator: ", "), privacy: .public)")
        for n in plan {
            let c = UNMutableNotificationContent()
            c.title = n.title
            c.body = n.body
            c.sound = .default
            c.threadIdentifier = n.kind == .pump ? "pump" : "sleep"
            let delay = max(1, n.fireDate.timeIntervalSinceNow)
            logger.info("Planlagt \(n.id, privacy: .public) kl. \(Format.clock(n.fireDate), privacy: .public): \(n.body, privacy: .public)")
            center.add(UNNotificationRequest(identifier: n.id, content: c,
                                             trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)))
        }
    }

    // Vis også beskeden, når appen er åben
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
