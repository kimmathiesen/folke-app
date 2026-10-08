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

    /// Minutter før næste søvn («Tid til at slappe af») og efter («… virker meget frisk»), valgt på denne enhed.
    static var leadMin: Int {
        get { defaults.object(forKey: "folke.leadMin") as? Int ?? NotificationPlanner.leadMin }
        set { defaults.set(newValue, forKey: "folke.leadMin") }
    }

    static var overdueMin: Int {
        get { defaults.object(forKey: "folke.overdueMin") as? Int ?? NotificationPlanner.overdueMin }
        set { defaults.set(newValue, forKey: "folke.overdueMin") }
    }

    /// Til Indstillinger (observeres, så valget vises med det samme)
    private(set) var leadMin = Notifier.leadMin
    private(set) var overdueMin = Notifier.overdueMin

    func setMinutes(lead: Int? = nil, overdue: Int? = nil) {
        if let lead { Self.leadMin = lead; leadMin = lead }
        if let overdue { Self.overdueMin = overdue; overdueMin = overdue }
        lastPlan = nil
    }

    static var log: NotificationLog {
        get {
            defaults.data(forKey: "folke.notificationLog")
                .flatMap { try? JSONDecoder().decode(NotificationLog.self, from: $0) } ?? NotificationLog()
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "folke.notificationLog") }
    }

    /// Planlæg forfra (fra appens skærm). Gentages kun, hvis planen har ændret sig.
    func reschedule(store: FolkeStore, now: Date = .now) {
        guard status == .allowed else { return }
        let (plan, scopes) = Self.plan(store: store, now: now, enabled: enabled)
        if plan == lastPlan { return }
        lastPlan = plan
        Self.apply(plan, scopes: scopes)
    }

    /// Planlæg forfra uden appens skærm (App Intents fra Siri, widgets og Live Activity).
    static func reschedule(store: FolkeStore, now: Date = .now) async {
        guard await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized else { return }
        let (plan, scopes) = plan(store: store, now: now, enabled: enabledKinds)
        apply(plan, scopes: scopes)
    }

    /// Søvnbeskeder for hvert barn og én påmindelse om udpumpning for familien. Uden Folke Plus regnes søvnbeskederne
    /// ud fra den enkle forudsigelse. Ved flere børn får hvert barn sin egen besked (id og log pr. barn, navnet som titel).
    private static func plan(store: FolkeStore, now: Date, enabled: Set<NotificationKind>)
        -> (plan: [PlannedNotification], scopes: [String]) {
        let plus = FolkeShared.plus(now: now).unlocked
        let kids = store.children()
        let saved = store.currentChildID
        defer { store.currentChildID = saved }
        let planner = NotificationPlanner()
        var log = log
        var out: [PlannedNotification] = []
        var scopes = [""]
        for c in kids {
            store.currentChildID = c.id
            let many = kids.count > 1
            let scope = many ? (c.id?.uuidString ?? "") : ""
            scopes.append(scope)
            let input = NotificationPlanner.Input(
                now: now, prediction: plus ? store.prediction(now: now) : store.basicPrediction(now: now),
                sleeping: store.runningSleep() != nil, childName: c.name ?? "", enabled: enabled.subtracting([.pump]),
                scope: scope, title: many ? (c.name ?? "Søvn") : "Søvn", leadMin: leadMin, overdueMin: overdueMin)
            let r = planner.plan(input, log: log)
            out += r.notifications
            log = r.log
        }
        let f = store.family()
        let pump = NotificationPlanner.Input(
            now: now, prediction: nil, sleeping: false, childName: "", enabled: enabled.intersection([.pump]),
            pumpFeature: f?.featurePump ?? false, pumpRemindHours: f?.pumpRemindHours ?? 3, lastPump: store.lastPumping(now: now))
        let r = planner.plan(pump, log: log)
        out += r.notifications
        Self.log = r.log
        return (out, scopes)
    }

    /// Fast id pr. type (og barn), så en ny plan erstatter den gamle. Typer uden plan fjernes.
    private static func apply(_ plan: [PlannedNotification], scopes: [String]) {
        let center = UNUserNotificationCenter.current()
        let ids = NotificationKind.allCases.flatMap { k in scopes.map { PlannedNotification.id(k, scope: $0) } }
        let removed = ids.filter { id in !plan.contains { $0.id == id } }
        center.removePendingNotificationRequests(withIdentifiers: removed)
        logger.info("Fjernet: \(removed.joined(separator: ", "), privacy: .public)")
        for n in plan {
            let c = UNMutableNotificationContent()
            c.title = n.title
            c.body = n.body
            c.sound = .default
            c.threadIdentifier = n.kind == .pump ? "pump" : "sleep" + n.scope
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
