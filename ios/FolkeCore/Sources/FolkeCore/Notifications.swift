import Foundation

/// Beskedtyper. Hver enhed slår dem til og fra for sig selv.
public enum NotificationKind: String, CaseIterable, Codable, Sendable {
    case sleepSoon = "sleep_soon"
    case overdue
    case pump

    public static let defaultsOn: Set<NotificationKind> = [.sleepSoon, .overdue]
}

/// En lokal notifikation, der skal planlægges. `id` er fast pr. type (og barn), så en ny plan erstatter den gamle.
public struct PlannedNotification: Equatable, Sendable {
    public var kind: NotificationKind
    public var fireDate: Date
    public var title: String
    public var body: String
    /// Barnets id ved flere børn ("" for udpumpning og ved ét barn)
    public var scope: String = ""

    public var id: String { Self.id(kind, scope: scope) }

    public static func id(_ kind: NotificationKind, scope: String) -> String {
        scope.isEmpty ? kind.rawValue : "\(kind.rawValue).\(scope)"
    }
}

/// Hvad der allerede er planlagt (eller sendt), så hver besked højst kommer én gang
/// pr. forudsigelse eller udpumpning. Gemmes pr. enhed.
public struct NotificationLog: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var key: String
        public var fireDate: Date
    }

    public var entries: [String: Entry] = [:]

    public init() {}
}

/// Regler for lokale notifikationer (port af `folke.main` og `pump_reminder` i app.py).
public struct NotificationPlanner: Sendable {
    public static let leadMin = 30
    public static let overdueMin = 15
    /// `overdue` sendes ikke mere end 2 timer for sent.
    public static let overdueMaxMin = 120
    /// Ingen påmindelser om udpumpning mellem 22 og 7.
    public static let quiet = (from: 22, to: 7)

    public struct Input: Sendable {
        public var now: Date
        public var prediction: Prediction?
        public var sleeping: Bool
        public var childName: String
        public var enabled: Set<NotificationKind>
        /// Udpumpning slået til for familien, og påmindelse efter så mange timer (0 = fra).
        public var pumpFeature: Bool
        public var pumpRemindHours: Double
        public var lastPump: (id: UUID, time: Date)?
        /// Ved flere børn: barnets id (adskiller beskeder og log pr. barn), og titlen bliver barnets navn
        public var scope: String
        public var title: String

        public init(now: Date, prediction: Prediction?, sleeping: Bool, childName: String,
                    enabled: Set<NotificationKind>, pumpFeature: Bool = false, pumpRemindHours: Double = 3,
                    lastPump: (id: UUID, time: Date)? = nil, scope: String = "", title: String = "Søvn") {
            self.scope = scope
            self.title = title
            self.now = now
            self.prediction = prediction
            self.sleeping = sleeping
            self.childName = childName
            self.enabled = enabled
            self.pumpFeature = pumpFeature
            self.pumpRemindHours = pumpRemindHours
            self.lastPump = lastPump
        }
    }

    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Notifikationerne, der skal ligge klar nu, og den opdaterede log.
    /// Ligger tidspunktet allerede bag os, men inden for det tilladte, sendes beskeden med det samme (fireDate = now),
    /// medmindre loggen viser, at den allerede er sendt.
    public func plan(_ input: Input, log: NotificationLog) -> (notifications: [PlannedNotification], log: NotificationLog) {
        var out: [PlannedNotification] = []
        var log = log
        let now = input.now

        func add(_ kind: NotificationKind, key: String, at fire: Date, latest: Date, title: String, body: String) {
            guard input.enabled.contains(kind), latest >= now else { return }
            let scope = kind == .pump ? "" : input.scope
            let id = PlannedNotification.id(kind, scope: scope)
            if let e = log.entries[id], e.key == key, e.fireDate <= now {
                return // allerede sendt
            }
            let when = max(fire, now)
            log.entries[id] = .init(key: key, fireDate: when)
            out.append(PlannedNotification(kind: kind, fireDate: when, title: title, body: body, scope: scope))
        }

        if let p = input.prediction, !input.sleeping {
            let key = p.lastID.uuidString
            add(.sleepSoon, key: key, at: p.time.addingTimeInterval(-Double(Self.leadMin) * 60), latest: p.time,
                title: input.title, body: soonText(p))
            add(.overdue, key: key, at: p.time.addingTimeInterval(Double(Self.overdueMin) * 60),
                latest: p.time.addingTimeInterval(Double(Self.overdueMaxMin) * 60),
                title: input.title, body: overdueText(p, name: input.childName))
        }

        if input.pumpFeature, input.pumpRemindHours > 0, let last = input.lastPump {
            // Er tiden allerede gået, sendes den nu, men aldrig mellem 22 og 7. Timerne regnes fra afsendelsen (som app.py)
            let fire = outsideQuiet(max(last.time.addingTimeInterval(input.pumpRemindHours * 3600), now))
            let hours = fire.timeIntervalSince(last.time) / 3600
            add(.pump, key: last.id.uuidString, at: fire, latest: .distantFuture, title: "Udpumpning",
                body: "Det er \(String(format: "%.0f", hours)) timer siden sidste udpumpning (kl. \(clock(last.time)))")
        }
        return (out, log)
    }

    public func soonText(_ p: Prediction) -> String {
        "Tid til at slappe af. \(p.kind == .nap ? "Næste lur" : "Sengetid") ca. kl. \(clock(p.time))"
    }

    public func overdueText(_ p: Prediction, name: String) -> String {
        let what = p.kind == .nap ? "en lur" : "at putte til natten"
        return "\(name.isEmpty ? "Babyen" : name) virker meget frisk. Prøv alligevel \(what)"
    }

    /// Flytter et tidspunkt mellem 22 og 7 til kl. 7.
    public func outsideQuiet(_ date: Date) -> Date {
        let h = calendar.component(.hour, from: date)
        guard h >= Self.quiet.from || h < Self.quiet.to else { return date }
        var day = calendar.startOfDay(for: date)
        if h >= Self.quiet.from {
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return calendar.date(bySettingHour: Self.quiet.to, minute: 0, second: 0, of: day)!
    }

    func clock(_ d: Date) -> String {
        Format.clock(d, calendar: calendar)
    }
}
