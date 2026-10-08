import CoreData
import Foundation

/// Opvågninger om natten (som `night_wake` i webappen): «Vågnede» og «Sover igen», mens natten kører.
public struct WakeItem: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var start: Date
    /// nil = vågen nu
    public var end: Date?

    /// Minutter vågen (en åben opvågning tæller til `now`)
    public func minutes(now: Date = .now) -> Double {
        max(0, (end ?? now).timeIntervalSince(start) / 60)
    }
}

public extension FolkeStore {
    /// Det valgte barns opvågninger, der startede i [start, end] (end nil = til nu), ældste først.
    func wakes(from start: Date, to end: Date? = nil) -> [WakeItem] {
        let p = end.map { NSPredicate(format: "start >= %@ AND start <= %@", start as NSDate, $0 as NSDate) }
            ?? NSPredicate(format: "start >= %@", start as NSDate)
        return fetch(NightWake.self, forChild(p), sort: [NSSortDescriptor(key: "start", ascending: true)]).compactMap { w in
            guard let id = w.id, let s = w.start else { return nil }
            return WakeItem(id: id, start: s, end: w.end)
        }
    }

    /// En opvågning, han ikke er faldet i søvn igen efter.
    func openWake() -> NightWake? {
        fetch(NightWake.self, forChild(NSPredicate(format: "end == nil")), limit: 1).first
    }

    /// «Vågnede»: kun mens en søvn kører. To tryk giver ikke to opvågninger.
    func startWake(by role: Role?, now: Date = .now) throws {
        guard runningSleep() != nil, openWake() == nil else { return }
        let c = child()
        let w = insert(NightWake.self, child: c)
        w.id = UUID()
        w.start = now
        w.createdBy = role?.rawValue
        w.child = c
        try save()
    }

    /// «Sover igen»
    func stopWake(now: Date = .now) throws {
        guard let w = openWake() else { return }
        w.end = max(now, w.start ?? now)
        try save()
    }

    func deleteWake(id: UUID) throws {
        if let w = fetch(NightWake.self, NSPredicate(format: "id == %@", id as CVarArg), limit: 1).first {
            try delete(w)
        }
    }

    /// Slet en søvn; er det en nat, følger opvågningerne i den med.
    func deleteSleep(_ s: Sleep) throws {
        if !s.nap, let a = s.start, let b = s.end {
            for w in fetch(NightWake.self, forChild(NSPredicate(format: "start >= %@ AND start <= %@", a as NSDate, b as NSDate))) {
                context.delete(w)
            }
        }
        try delete(s)
    }
}
