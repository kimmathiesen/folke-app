import Foundation

/// Søvn i tal (port af `stats.py`, samme testdata i tests/fixtures/stats): de seneste 14 hele dage og gennemsnit for
/// de seneste 7 dage mod ugen før. En dag er lurene, der starter den dag, og natten, der starter samme aften (minus tid
/// vågen om natten). «Vågnede» er, da natten før sluttede. Dage uden nat tæller ikke med i gennemsnittene.
public struct SleepStats: Equatable, Sendable {
    public struct Day: Equatable, Sendable {
        public var date: Date
        /// false = intet registreret den dag (resten er så tomt)
        public var registered = false
        public var naps = 0
        public var dayMin = 0
        public var nightMin: Int?
        public var totalMin: Int?
        /// Minutter efter midnat
        public var bed: Int?
        public var wake: Int?
        public var wakes: Int?
        public var napLen: Int?
    }

    public struct Summary: Equatable, Sendable {
        public var days = 0
        public var totalMin, nightMin, dayMin, napLen, bed, wake: Int?
        public var naps, wakes: Double?
    }

    public var days: [Day]
    public var week: Summary
    public var prev: Summary
    public var text: String?

    public static let dayCount = 14

    /// Python `round` (halve runder til lige), som `.toNearestOrEven`
    static func round(_ x: Double) -> Int { Int(x.rounded(.toNearestOrEven)) }

    static func day(_ sleeps: [SleepSample], _ wakes: [WakeItem], _ d: Date, calendar: Calendar) -> Day {
        func mins(_ a: Date, _ b: Date) -> Double { b.timeIntervalSince(a) / 60 }
        func clock(_ t: Date) -> Int {
            let c = calendar.dateComponents([.hour, .minute], from: t)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        let naps = sleeps.filter { $0.nap && calendar.isDate($0.start, inSameDayAs: d) }
        let nights = sleeps.filter { !$0.nap && calendar.isDate($0.start, inSameDayAs: d) }
        let before = sleeps.filter { !$0.nap && calendar.isDate($0.end, inSameDayAs: d) && $0.start < d }
        var out = Day(date: d)
        guard !naps.isEmpty || !nights.isEmpty else { return out }
        out.registered = true
        // Den længste nat (første ved lige lange, som Pythons max)
        let n = nights.reduce(nil as SleepSample?) { best, s in
            best.map { mins($0.start, $0.end) >= mins(s.start, s.end) ? $0 : s } ?? s
        }
        let ws = n.map { n in wakes.filter { n.start <= $0.start && $0.start <= n.end } } ?? []
        let awake = n.map { n in ws.reduce(0.0) { $0 + mins($1.start, min($1.end ?? n.end, n.end)) } } ?? 0
        let napMin = naps.reduce(0.0) { $0 + mins($1.start, $1.end) }
        out.naps = naps.count
        out.dayMin = round(napMin)
        if let n {
            let night = mins(n.start, n.end) - awake
            out.nightMin = round(night)
            out.totalMin = round(napMin + night)
            out.bed = clock(n.start)
            out.wakes = ws.count
        }
        if let b = before.reduce(nil as SleepSample?, { best, s in best.map { $0.end >= s.end ? $0 : s } ?? s }) {
            out.wake = clock(b.end)
        }
        out.napLen = naps.isEmpty ? nil : round(napMin / Double(naps.count))
        return out
    }

    static func summary(_ days: [Day], tracksWakes: Bool) -> Summary {
        let full = days.filter { $0.nightMin != nil }
        func avg(_ xs: [Int?]) -> Int? {
            let v = xs.compactMap { $0 }
            return v.isEmpty ? nil : round(Double(v.reduce(0, +)) / Double(v.count))
        }
        func avg1(_ xs: [Int?]) -> Double? {
            let v = xs.compactMap { $0 }
            return v.isEmpty ? nil : Double(round(Double(v.reduce(0, +)) / Double(v.count) * 10)) / 10
        }
        func medianClock(_ xs: [Int?], evening: Bool = false) -> Int? {
            let v = xs.compactMap { $0 }.map { evening && $0 < 12 * 60 ? $0 + 1440 : $0 }
            return v.isEmpty ? nil : round(Predictor.median(v.map(Double.init))) % 1440
        }
        return Summary(days: full.count, totalMin: avg(full.map(\.totalMin)), nightMin: avg(full.map(\.nightMin)),
                       dayMin: avg(full.map { $0.dayMin }), napLen: avg(full.map(\.napLen)),
                       bed: medianClock(full.map(\.bed), evening: true), wake: medianClock(full.map(\.wake)),
                       naps: avg1(full.map { $0.naps }), wakes: tracksWakes ? avg1(full.map(\.wakes)) : nil)
    }

    static func duration(_ m: Int) -> String {
        let h = m / 60, r = m % 60
        return h > 0 && r > 0 ? "\(h) t \(r) min" : h > 0 ? "\(h) t" : "\(r) min"
    }

    public static func make(sleeps: [SleepSample], wakes: [WakeItem], now: Date, name: String,
                            calendar: Calendar = .current) -> SleepStats {
        let today = calendar.startOfDay(for: now)
        let dates = (1...dayCount).reversed().map { calendar.date(byAdding: .day, value: -$0, to: today)! }
        let days = dates.map { day(sleeps, wakes, $0, calendar: calendar) }
        let tracks = !wakes.isEmpty
        let week = summary(Array(days[7...]), tracksWakes: tracks), prev = summary(Array(days[..<7]), tracksWakes: tracks)
        var text: String?
        if week.days > 0, let t = week.totalMin, let n = week.nightMin {
            text = "\(name.isEmpty ? "Jeres barn" : name) sover i gennemsnit \(duration(t)) i døgnet, heraf \(duration(n)) om natten."
        }
        return SleepStats(days: days, week: week, prev: prev, text: text)
    }
}

public extension FolkeStore {
    /// Søvn i tal for det valgte barn
    func sleepStats(now: Date = .now) -> SleepStats {
        let since = now.addingTimeInterval(-Double(SleepStats.dayCount + 2) * 86400)
        return SleepStats.make(sleeps: sleeps(since: since).compactMap(\.sample), wakes: wakes(from: since), now: now,
                               name: child()?.name ?? "", calendar: calendar)
    }
}
