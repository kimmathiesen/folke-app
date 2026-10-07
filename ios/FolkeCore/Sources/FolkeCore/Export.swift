import CoreData
import Foundation

/// Eksport som CSV (PLAN.md milepæl 10: dine data er dine, fx til sundhedsplejersken).
/// Semikolon og decimalkomma, så dansk Excel og Numbers åbner filerne direkte. Tider i lokal tid.
public struct CSVFile: Equatable, Sendable {
    public var name: String
    public var text: String
    public var rows: Int

    /// UTF-8 med BOM, så Excel viser æ, ø og å rigtigt.
    public var data: Data { Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8) }
}

public enum CSV {
    public static func line(_ fields: [String]) -> String {
        fields.map { f in
            f.contains(where: { ";\"\n\r".contains($0) }) ? "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : f
        }.joined(separator: ";")
    }

    static func table(_ header: [String], _ rows: [[String]]) -> String {
        ([header] + rows).map(line).joined(separator: "\r\n") + "\r\n"
    }
}

/// Danske navne i eksporten.
public enum FKLabels {
    public static func feeding(_ kind: FeedKind) -> String {
        switch kind {
        case .left: "Amning venstre"
        case .right: "Amning højre"
        case .both: "Amning begge"
        case .bottle: "Flaske"
        case .solid: "Fast føde"
        }
    }

    public static func milk(_ m: Milk) -> String { m == .formula ? "Modermælkserstatning" : "Modermælk" }
}

public extension FolkeStore {
    /// Fire filer: søvn, mad, udpumpning og vækst (ældste først). Filnavnene får dagens dato.
    func csvExport(now: Date = .now) -> [CSVFile] {
        let cal = calendar
        func stamp(_ d: Date?) -> String {
            guard let d else { return "" }
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
            return String(format: "%04d-%02d-%02d %02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!)
        }
        func date(_ d: Date?) -> String { String(stamp(d).prefix(10)) }
        func num(_ v: Double) -> String { v > 0 ? Format.number(v) : "" }
        let today = date(now)

        let sleeps = fetch(Sleep.self, sort: [NSSortDescriptor(key: "start", ascending: true)])
        let sleepRows = sleeps.map { s in
            [stamp(s.start), stamp(s.end),
             s.start.flatMap { a in s.end.map { String(Int($0.timeIntervalSince(a) / 60)) } } ?? "",
             s.nap ? "Lur" : "Nat"]
        }

        let feeds = fetch(Feeding.self, sort: [NSSortDescriptor(key: "time", ascending: true)])
        let feedRows = feeds.map { f in
            let kind = FeedKind(rawValue: f.kind ?? "")
            return [stamp(f.time), kind.map(FKLabels.feeding) ?? (f.kind ?? ""), num(f.amountMl),
                    kind == .bottle ? FKLabels.milk(Milk(rawValue: f.milk ?? "") ?? .breast) : "", f.note ?? ""]
        }

        let pumps = fetch(Pumping.self, sort: [NSSortDescriptor(key: "time", ascending: true)])
        let pumpRows = pumps.map { p in
            [stamp(p.time), num(p.amountMl), p.side.flatMap { Side(rawValue: $0)?.label } ?? "", num(p.minutes)]
        }

        let growth = fetch(Growth.self, sort: [NSSortDescriptor(key: "date", ascending: true)])
        let growthRows = growth.map { g in [date(g.date), num(g.weightKg), num(g.lengthCm), num(g.headCm)] }

        return [
            CSVFile(name: "folke-soevn-\(today).csv",
                    text: CSV.table(["Start", "Slut", "Minutter", "Type"], sleepRows), rows: sleepRows.count),
            CSVFile(name: "folke-mad-\(today).csv",
                    text: CSV.table(["Tidspunkt", "Type", "Mængde (ml)", "Mælk", "Note"], feedRows), rows: feedRows.count),
            CSVFile(name: "folke-udpumpning-\(today).csv",
                    text: CSV.table(["Tidspunkt", "Mængde (ml)", "Side", "Minutter"], pumpRows), rows: pumpRows.count),
            CSVFile(name: "folke-vaekst-\(today).csv",
                    text: CSV.table(["Dato", "Vægt (kg)", "Længde (cm)", "Hovedomfang (cm)"], growthRows),
                    rows: growthRows.count),
        ]
    }
}
