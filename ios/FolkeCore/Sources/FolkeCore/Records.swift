import CoreData
import Foundation

/// Måltider (port af `/api/feed` i app.py).
public enum FeedKind: String, CaseIterable, Sendable {
    case left, right, both, bottle, solid

    public var isBreast: Bool { [.left, .right, .both].contains(self) }
}

public enum Milk: String, CaseIterable, Sendable {
    case breast, formula
}

/// Side ved amning og udpumpning.
public enum Side: String, CaseIterable, Sendable {
    case left, right, both

    public var label: String {
        switch self {
        case .left: "venstre"
        case .right: "højre"
        case .both: "begge"
        }
    }
}

public enum RecordError: Error, Equatable, LocalizedError {
    case invalidMeal
    case invalidAmount
    case invalidMinutes
    case inFuture

    public var errorDescription: String? {
        switch self {
        case .invalidMeal: "Ugyldigt måltid"
        case .invalidAmount: "Ugyldig mængde"
        case .invalidMinutes: "Minutter skal være mellem 1 og 180"
        case .inFuture: "Tidspunktet ligger i fremtiden"
        }
    }
}

/// Opsummering til udpumpningskortet på forsiden.
public struct PumpSummary: Equatable, Sendable {
    public var todayCount: Int
    public var todayMl: Int
    public var last: Date?

    public init(todayCount: Int, todayMl: Int, last: Date?) {
        self.todayCount = todayCount
        self.todayMl = todayMl
        self.last = last
    }
}

public extension FolkeStore {
    // MARK: Søvn: ret og slet

    /// Ret start, slut og lur/nat på en afsluttet søvn.
    func editSleep(_ s: Sleep, start: Date, end: Date, nap: Bool, now: Date = .now) throws {
        try SleepRules.checkEdit(start: start, end: end, now: now)
        s.start = start
        s.end = end
        s.nap = nap
        try save()
    }

    func delete(_ obj: NSManagedObject) throws {
        context.delete(obj)
        try save()
    }

    func sleep(id: UUID) -> Sleep? {
        fetch(Sleep.self, NSPredicate(format: "id == %@", id as CVarArg), limit: 1).first
    }

    // MARK: Mad

    /// Log et måltid. Flaske kræver 0 < ml ≤ 500. Noten til fast føde afkortes til 200 tegn.
    @discardableResult
    func addFeeding(_ kind: FeedKind, amountMl: Double? = nil, milk: Milk = .breast, note: String = "",
                    at time: Date? = nil, now: Date = .now) throws -> Feeding {
        if kind == .bottle {
            guard let amountMl, amountMl > 0, amountMl <= 500 else { throw RecordError.invalidMeal }
        }
        let c = child()
        let f = insert(Feeding.self, child: c)
        f.id = UUID()
        f.time = time ?? now
        f.kind = kind.rawValue
        if kind == .bottle {
            f.amountMl = amountMl ?? 0
            f.milk = milk.rawValue
        }
        if kind == .solid {
            let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
            f.note = n.isEmpty ? nil : String(n.prefix(200))
        }
        f.child = c
        try save()
        return f
    }

    /// Seneste måltid de sidste 2 døgn.
    func lastFeeding(now: Date = .now) -> Feeding? {
        fetch(Feeding.self, NSPredicate(format: "time >= %@", now.addingTimeInterval(-2 * 86400) as NSDate),
              sort: [NSSortDescriptor(key: "time", ascending: false)], limit: 1).first
    }

    /// Seneste amning de sidste 60 dage (til forslaget «Skjul Amning»).
    func lastBreastFeed(now: Date = .now) -> Date? {
        fetch(Feeding.self, NSPredicate(format: "time >= %@ AND kind IN %@", now.addingTimeInterval(-60 * 86400) as NSDate,
                                        ["left", "right", "both"]),
              sort: [NSSortDescriptor(key: "time", ascending: false)], limit: 1).first?.time
    }

    // MARK: Udpumpning

    /// Mængde (0 < ml ≤ 1000), side og minutter (0 < min ≤ 180, valgfri).
    static func checkPump(amountMl: Double, minutes: Double?) throws {
        guard amountMl > 0, amountMl <= 1000 else { throw RecordError.invalidAmount }
        if let minutes, !(minutes > 0 && minutes <= 180) { throw RecordError.invalidMinutes }
    }

    @discardableResult
    func addPumping(amountMl: Double, side: Side? = nil, minutes: Double? = nil, at time: Date? = nil,
                    now: Date = .now) throws -> Pumping {
        try Self.checkPump(amountMl: amountMl, minutes: minutes)
        let c = child()
        let p = insert(Pumping.self, child: c)
        p.id = UUID()
        p.time = time ?? now
        p.amountMl = amountMl
        p.side = side?.rawValue
        p.minutes = minutes ?? 0
        p.child = c
        try save()
        return p
    }

    func editPumping(_ p: Pumping, time: Date, amountMl: Double, side: Side?, minutes: Double?, now: Date = .now) throws {
        try Self.checkPump(amountMl: amountMl, minutes: minutes)
        if time > now.addingTimeInterval(60) { throw RecordError.inFuture }
        p.time = time
        p.amountMl = amountMl
        p.side = side?.rawValue
        p.minutes = minutes ?? 0
        try save()
    }

    /// Udpumpninger efter `since`, ældste først.
    func pumpings(since: Date) -> [Pumping] {
        fetch(Pumping.self, NSPredicate(format: "time >= %@", since as NSDate),
              sort: [NSSortDescriptor(key: "time", ascending: true)])
    }

    /// «I dag: 3 gange · 340 ml» og seneste udpumpning (de sidste 2 døgn).
    func pumpSummary(now: Date = .now) -> PumpSummary {
        let rows = pumpings(since: now.addingTimeInterval(-2 * 86400))
        let today = rows.filter { $0.time.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
        return PumpSummary(todayCount: today.count,
                           todayMl: Int(today.reduce(0) { $0 + $1.amountMl }.rounded(.toNearestOrEven)),
                           last: rows.last?.time)
    }

    // MARK: Forslag og funktioner

    func suggestions(now: Date = .now) -> [Suggestions.Suggestion] {
        guard let c = child(), let birth = c.birthDate, let s = settings() else { return [] }
        return Suggestions.compute(now: now, birthDate: birth, sex: Sex(rawValue: c.sex ?? "") ?? .boy,
                                   solids: s.featureSolids, breast: s.featureBreast,
                                   lastBreastFeed: s.featureBreast ? lastBreastFeed(now: now) : nil,
                                   answers: s.answers, calendar: calendar)
    }

    /// Ja slår fast føde til eller skjuler amning. Ikke nu = 30 dage. Aldrig = aldrig igen.
    func answer(_ id: Suggestions.ID, _ answer: Suggestions.Answer, now: Date = .now) throws {
        guard let s = settings() else { return }
        if answer == .yes {
            switch id {
            case .solids: s.featureSolids = true
            case .hideBreast: s.featureBreast = false
            }
        }
        var a = s.answers
        a[id] = Suggestions.stored(for: answer, now: now)
        s.answers = a
        try save()
    }
}
