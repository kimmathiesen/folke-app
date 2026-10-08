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

    /// Hvor sengetiden kommer fra: hans egne aftener (mindst 3) eller standarden 19:30
    public enum BedBasis: String, Sendable {
        case own, `default`
    }

    public var kind: Kind
    public var time: Date
    public var windowMin: Int
    public var source: Source
    public var lastID: UUID
    /// 0 = efter natten, 1 = efter 1. lur ...
    public var pos: Int = 0
    public var bedBasis: BedBasis = .default
    /// Længden af en kort lur lige før (min), så vinduet er kortere end normalt
    public var short: Int?
    /// Minutter sengetiden er rykket frem
    public var bedShift: Int = 0
    /// Sengetiden er regnet fra aftenluren, der er sovet
    public var afterCatnap = false

    public init(kind: Kind, time: Date, windowMin: Int, source: Source, lastID: UUID, pos: Int = 0,
                bedBasis: BedBasis = .default, short: Int? = nil, bedShift: Int = 0, afterCatnap: Bool = false) {
        self.afterCatnap = afterCatnap
        self.short = short
        self.bedShift = bedShift
        self.kind = kind
        self.time = time
        self.windowMin = windowMin
        self.source = source
        self.lastID = lastID
        self.pos = pos
        self.bedBasis = bedBasis
    }
}

/// Port af `folke.predict` på branchen `standalone`.
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

    /// Næste søvn = første punkt i dagsplanen, uden genberegning ved misset lur (`predict` i folke.py).
    /// Notifikationerne bruger den, så «virker meget frisk» kommer på det oprindelige tidspunkt.
    public static func predict(_ sleeps: [SleepSample], birthDate: Date, now: Date,
                               calendar: Calendar = .current) -> Prediction? {
        guard let p = DayPlanner.plan(sleeps, birthDate: birthDate, now: now, replan: false, calendar: calendar),
              let first = p.items.first else { return nil }
        return Prediction(kind: first.kind, time: first.start, windowMin: p.firstWindow, source: p.source,
                          lastID: p.lastID, pos: p.pos, bedBasis: p.bedBasis, short: p.short, bedShift: p.bedShift,
                          afterCatnap: p.afterCatnap)
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
