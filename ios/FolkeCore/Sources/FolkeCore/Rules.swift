import Foundation

/// Mor eller far. Gemmes kun på enheden.
public enum Role: String, CaseIterable, Codable, Sendable {
    case mor, far
}

/// Tekstformater som i webappen.
public enum Format {
    /// "13:40"
    public static func clock(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// "45 min" eller "1 t 20 min" (som `dur` i index.html).
    public static func duration(minutes m: Int) -> String {
        m < 60 ? "\(m) min" : "\(m / 60) t \(m % 60) min"
    }

    /// "01:20:05" til tælleren i ringen.
    public static func counter(seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }

    /// Genitiv: «Folkes», men «Mads'».
    public static func genitive(_ name: String) -> String {
        guard let last = name.last?.lowercased() else { return name }
        return ["s", "x", "z"].contains(last) ? name + "'" : name + "s"
    }

    /// «Hej Folkes mor», eller «Baby Søvn» uden navn eller rolle.
    public static func greeting(name: String, role: Role?) -> String {
        guard !name.isEmpty, let role else { return "Baby Søvn" }
        return "Hej \(genitive(name)) \(role.rawValue)"
    }

    /// Barnets navn: mellemrum ryddet op, 1-40 tegn.
    public static func cleanName(_ s: String) -> String? {
        let name = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (1...40).contains(name.count) ? name : nil
    }
}

public enum SleepRules {
    public enum Failure: Error, Equatable, LocalizedError {
        case startBeforePreviousEnd(Date)
        case wakeBeforeStart(Date)
        case endBeforeStart
        case endInFuture

        public var errorDescription: String? {
            switch self {
            case .startBeforePreviousEnd(let d): "Forrige søvn sluttede kl. \(Format.clock(d))"
            case .wakeBeforeStart(let d): "Søvnen startede kl. \(Format.clock(d))"
            case .endBeforeStart: "Sluttid skal være efter starttid"
            case .endInFuture: "Sluttid ligger i fremtiden"
            }
        }
    }

    /// Et klokkeslæt i dag, eller i går, hvis det ligger i fremtiden.
    public static func resolve(hour: Int, minute: Int, now: Date, calendar: Calendar = .current) -> Date {
        let t = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)!
        return t > now ? calendar.date(byAdding: .day, value: -1, to: t)! : t
    }

    /// «Faldt i søvn kl.»: en start før forrige søvns slut afvises.
    public static func checkStart(_ start: Date, previousEnd: Date?) throws(Failure) {
        if let previousEnd, start < previousEnd {
            throw .startBeforePreviousEnd(previousEnd)
        }
    }

    /// «Vågnede kl.»: en opvågning før (eller lig med) start afvises.
    public static func checkWake(_ end: Date, start: Date) throws(Failure) {
        if end <= start {
            throw .wakeBeforeStart(start)
        }
    }

    /// Ret søvn: slut efter start og ikke i fremtiden (et minuts slæk).
    public static func checkEdit(start: Date, end: Date, now: Date) throws(Failure) {
        if end <= start { throw .endBeforeStart }
        if end > now.addingTimeInterval(60) { throw .endInFuture }
    }
}

/// Forslag på forsiden (port af `suggestions` i app.py). Intet ændres uden svar.
public enum Suggestions {
    public enum ID: String, CaseIterable, Codable, Sendable {
        case solids
        case hideBreast = "hide_breast"
    }

    public enum Answer: String, Codable, Sendable {
        case yes, later, never
    }

    /// Svaret, som det gemmes: «done», «never» eller «vis igen efter».
    public enum Stored: Codable, Equatable, Sendable {
        case done, never
        case snoozed(until: Date)
    }

    public struct Suggestion: Equatable, Sendable {
        public var id: ID
        public var text: String
    }

    public static let snoozeDays = 30
    public static let breastIdleDays = 21

    public static func open(_ s: Stored?, now: Date) -> Bool {
        switch s {
        case nil: true
        case .done, .never: false
        case .snoozed(let until): until < now
        }
    }

    public static func stored(for answer: Answer, now: Date) -> Stored {
        switch answer {
        case .yes: .done
        case .later: .snoozed(until: now.addingTimeInterval(Double(snoozeDays) * 86400))
        case .never: .never
        }
    }

    public static func compute(now: Date, birthDate: Date, sex: Sex, solids: Bool, breast: Bool,
                               lastBreastFeed: Date?, answers: [ID: Stored],
                               calendar: Calendar = .current) -> [Suggestion] {
        var out: [Suggestion] = []
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: birthDate),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        let months = Double(days) / 30.44
        if !solids, months >= 6, open(answers[.solids], now: now) {
            let pronoun = sex == .girl ? "Hun" : "Han"
            out.append(.init(id: .solids,
                             text: "\(pronoun) er nu \(Int(months)) måneder. Vil du tilføje «Fast føde» til Mad-kortet?"))
        }
        if breast, open(answers[.hideBreast], now: now), let last = lastBreastFeed {
            let idle = Int(now.timeIntervalSince(last) / 86400)
            if idle >= breastIdleDays {
                out.append(.init(id: .hideBreast,
                                 text: "Du har ikke registreret amning i \(idle / 7) uger. Skal Amning-knappen skjules?"))
            }
        }
        return out
    }
}
