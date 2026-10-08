import CoreData
import Foundation

/// Tvillinger: børn med samme fødselsdato som det valgte barn. Søvn kan startes og stoppes for dem alle på én gang.
public extension FolkeStore {
    /// De andre børn med samme fødselsdato som det valgte (tom, hvis barnet ikke er tvilling).
    func twins() -> [Child] {
        guard let c = child(), let birth = c.birthDate else { return [] }
        return children().filter { $0 != c && $0.birthDate.map { calendar.isDate($0, inSameDayAs: birth) } ?? false }
    }

    /// Kør `body` for hvert barn (som det valgte), og sæt det valgte barn tilbage bagefter.
    private func each(_ kids: [Child], _ body: () throws -> Void) rethrows {
        let saved = currentChildID
        defer { currentChildID = saved }
        for k in kids {
            currentChildID = k.id
            try body()
        }
    }

    /// Start søvn for det valgte barn og dets tvillinger (dem, der ikke allerede sover).
    func startSleepWithTwins(at start: Date? = nil, by role: Role?, now: Date = .now) throws {
        let kids = [child()].compactMap { $0 } + twins()
        try each(kids) {
            if runningSleep() == nil { try startSleep(at: start, by: role, now: now) }
        }
    }

    /// Stop søvn for det valgte barn og dets tvillinger. Lur eller nat gættes for hver ud fra start og længde.
    func stopSleepWithTwins(at end: Date? = nil, now: Date = .now) throws {
        let kids = [child()].compactMap { $0 } + twins()
        try each(kids) { try stopSleep(at: end, now: now) }
    }

    /// Hvornår hver tvilling faldt i søvn (nil = vågen), i samme rækkefølge som `twins()`.
    func twinsSleepingSince() -> [(child: Child, since: Date?)] {
        let kids = twins()
        var out: [(Child, Date?)] = []
        each(kids) { out.append((child()!, runningSleep()?.start)) }
        return out
    }
}
