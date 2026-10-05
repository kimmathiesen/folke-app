import Foundation

/// En afsluttet søvn, som forudsigelsen regner på (uafhængig af Core Data).
public struct SleepSample: Equatable, Sendable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var nap: Bool

    public init(id: UUID = UUID(), start: Date, end: Date, nap: Bool) {
        self.id = id
        self.start = start
        self.end = end
        self.nap = nap
    }
}

public struct Prediction: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case nap = "lur"
        case bedtime = "sengetid"
    }

    public enum Source: Equatable, Sendable {
        case position(Int)
        case allWindows
        case ageDefault

        public var text: String {
            switch self {
            case .position(let p): "eget mønster (position \(p))"
            case .allWindows: "gennemsnit af alle vinduer"
            case .ageDefault: "aldersbaseret standard"
            }
        }
    }

    public var kind: Kind
    public var time: Date
    public var windowMin: Int
    public var source: Source
    public var lastID: UUID
}

/// Port af `napper.predict` på branchen `standalone`.
public enum Predictor {
    /// Hvor mange dages søvn forudsigelsen bruger.
    public static let historyDays = 10
    /// Sengetid uden nok data: 19:30.
    public static let defaultBedtimeMin = 19 * 60 + 30

    /// Groft vågenvindue (minutter) efter alder. Bruges kun, til der er data nok.
    public static func defaultWindow(ageDays: Int) -> Int {
        let months = Double(ageDays) / 30.4
        for (limit, mins) in [(2.0, 60), (3, 75), (4, 90), (6, 120), (9, 150), (12, 180), (18, 210)] where months < limit {
            return mins
        }
        return 270
    }

    public static func predict(_ sleeps: [SleepSample], birthDate: Date, now: Date,
                               calendar: Calendar = .current) -> Prediction? {
        let sleeps = sleeps.sorted { $0.start < $1.start }
        guard let last = sleeps.last else { return nil }

        // Vågenvinduer pr. position på dagen (0 = morgen, 1 = efter 1. lur ...)
        var windows: [Int: [Double]] = [:]
        var allGaps: [Double] = []
        var pos = 0
        for (prev, next) in zip(sleeps, sleeps.dropFirst()) {
            pos = prev.nap ? pos + 1 : 0
            let gap = next.start.timeIntervalSince(prev.end) / 60
            if gap > 20 && gap < 480 {
                windows[pos, default: []].append(gap)
                allGaps.append(gap)
            }
        }

        // Position for den næste søvn
        pos = 0
        for s in sleeps {
            pos = s.nap ? pos + 1 : 0
        }

        let ageDays = calendar.dateComponents([.day], from: calendar.startOfDay(for: birthDate),
                                              to: calendar.startOfDay(for: now)).day ?? 0
        let samples = (windows[pos] ?? []).suffix(7)
        let window: Double
        let source: Prediction.Source
        if samples.count >= 3 {
            (window, source) = (median(Array(samples)), .position(pos))
        } else if allGaps.count >= 5 {
            (window, source) = (median(Array(allGaps.suffix(15))), .allWindows)
        } else {
            (window, source) = (Double(defaultWindow(ageDays: ageDays)), .ageDefault)
        }

        let nextStart = last.end.addingTimeInterval(window * 60)

        // Typisk sengetid = median af aftensøvne (kl. 17-24)
        let evenings: [Double] = sleeps.compactMap { s in
            let c = calendar.dateComponents([.hour, .minute], from: s.start)
            guard !s.nap, let h = c.hour, let m = c.minute, h >= 17 else { return nil }
            return Double(h * 60 + m)
        }
        let bedMin = evenings.count >= 3 ? Int(median(evenings)) : defaultBedtimeMin
        let bed = calendar.date(bySettingHour: bedMin / 60, minute: bedMin % 60, second: 0, of: nextStart) ?? nextStart

        let (kind, when): (Prediction.Kind, Date) = nextStart >= bed.addingTimeInterval(-60 * 60)
            ? (.bedtime, bed) : (.nap, nextStart)

        return Prediction(kind: kind, time: when, windowMin: Int(window.rounded(.toNearestOrEven)),
                          source: source, lastID: last.id)
    }

    /// Som Pythons `statistics.median`: ved et lige antal gennemsnittet af de to midterste.
    public static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        precondition(!s.isEmpty)
        let mid = s.count / 2
        return s.count % 2 == 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2
    }

    /// Gæt på lur eller nat, når en søvn startes: nat fra kl. 18 og før kl. 5.
    public static func napGuess(_ start: Date, calendar: Calendar = .current) -> Bool {
        let h = calendar.component(.hour, from: start)
        return !(h >= 18 || h < 5)
    }
}
