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

    /// "13.40": klokkeslæt i UI'et (dansk format som `hm` i index.html). Notifikationer og fejl bruger `clock`.
    public static func time(_ d: Date, calendar: Calendar = .current) -> String {
        clock(d, calendar: calendar).replacingOccurrences(of: ":", with: ".")
    }

    /// "for 1 t 10 min siden" uden «for» og «siden» (som `ago` i index.html).
    public static func ago(_ d: Date, now: Date) -> String {
        duration(minutes: max(0, Int(now.timeIntervalSince(d) / 60)))
    }

    /// Linjen med sidste måltid: «Flaske 120 ml kl. 14.05 · for 1 t 10 min siden».
    /// «Flaske», «Amning, venstre» … (som i Mad-kortet)
    public static func feedName(_ kind: FeedKind) -> String {
        switch kind {
        case .bottle: "Flaske"
        case .left: "Amning, venstre"
        case .right: "Amning, højre"
        case .both: "Amning"
        case .solid: "Fast føde"
        }
    }

    public static func lastFeed(kind: FeedKind, amountMl: Double, time: Date, now: Date,
                                calendar: Calendar = .current) -> String {
        let name = feedName(kind)
        let ml = amountMl > 0 ? " \(Int(amountMl.rounded())) ml" : ""
        return "\(name)\(ml) kl. \(Format.time(time, calendar: calendar)) · for \(ago(time, now: now)) siden"
    }

    /// «I dag: 3 gange · 340 ml · sidst kl. 14.20 · for 1 t 5 min siden» (som `pumpUI` i index.html).
    public static func pumpSummary(_ s: PumpSummary, now: Date, calendar: Calendar = .current) -> String {
        let last = s.last.map { "sidst kl. \(Format.time($0, calendar: calendar)) · for \(ago($0, now: now)) siden" }
        if s.todayCount > 0 {
            return "I dag: \(s.todayCount) \(s.todayCount > 1 ? "gange" : "gang") · \(s.todayMl) ml"
                + (last.map { " · " + $0 } ?? "")
        }
        return last.map { "Ingen i dag · " + $0 } ?? "Ingen udpumpninger endnu"
    }

    /// "45 min", "1 t" eller "1 t 20 min" (som `dur` i index.html).
    public static func duration(minutes m: Int) -> String {
        m < 60 ? "\(m) min" : "\(m / 60) t" + (m % 60 > 0 ? " \(m % 60) min" : "")
    }

    /// Forklaringen under «Næste lur» på almindeligt dansk (som `why` i index.html).
    public static func why(_ p: Prediction) -> String {
        if p.kind == .bedtime {
            if p.afterCatnap { return "Vågen ca. \(duration(minutes: p.windowMin)) efter aftenluren" }
            if p.bedShift > 0 { return "Rykket \(p.bedShift) min frem efter en dag med mindre søvn end normalt" }
            return p.bedBasis == .own ? "Sengetid ud fra de seneste aftener" : "Typisk sengetid (for lidt data endnu)"
        }
        if let short = p.short {
            return "Vågen ca. \(duration(minutes: p.windowMin)) efter en kort lur på \(short) min (kortere end normalt)"
        }
        let after: String
        switch p.source {
        case .position: after = p.pos > 0 ? " efter \(p.pos). lur" : " efter natten"
        default: after = ""
        }
        let basis = p.source == .ageDefault ? "typisk for alderen (for lidt data endnu)" : "ud fra de seneste dage"
        return "Vågen ca. \(duration(minutes: p.windowMin))\(after) · \(basis)"
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

/// Dagens søvn i listen: farve og ikon efter tidspunkt (`TL` i index.html).
public enum DayPart: Sendable {
    case night, morning, day, evening

    public static func of(start: Date, nap: Bool, calendar: Calendar = .current) -> DayPart {
        guard nap else { return .night }
        let h = calendar.component(.hour, from: start)
        return h < 11 ? .morning : h < 15 ? .day : .evening
    }

    public var color: RGB {
        switch self {
        case .night: RGB(hex: "#7c6ff0")
        case .morning: RGB(hex: "#e0a63c")
        case .day: RGB(hex: "#3f9be0")
        case .evening: RGB(hex: "#e8814f")
        }
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
        case hidePrediction = "hide_prediction"
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
    /// Forslaget om at skjule forudsigelsen: fra 2½ år, når der ikke er sovet lur i 2 uger (men søvn er registreret)
    public static let predictionMinMonths = 30.0
    public static let napIdleDays = 14

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
                               lastBreastFeed: Date?, answers: [ID: Stored], prediction: Bool = false,
                               lastNap: Date? = nil, sleptRecently: Bool = false,
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
        if prediction, sleptRecently, months >= predictionMinMonths, open(answers[.hidePrediction], now: now),
           lastNap.map({ now.timeIntervalSince($0) >= Double(napIdleDays) * 86400 }) ?? true {
            let pronoun = sex == .girl ? "Hun" : "Han"
            out.append(.init(id: .hidePrediction,
                             text: "\(pronoun) har ikke sovet lur i \(napIdleDays / 7) uger. Skal forudsigelsen af lure skjules? "
                                 + "Søvnloggen og resten bliver."))
        }
        return out
    }
}
