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
    /// Fire filer: søvn, mad, udpumpning og vækst (ældste først) for hele familien. Søvn, mad og vækst
    /// har barnets navn i første kolonne. Filnavnene får dagens dato.
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
        let fam = forFamily()
        let kids = NSPredicate(format: "child.family == %@", family() ?? NSNull())
        func name(_ c: Child?) -> String { c?.name ?? "" }

        let sleeps = fetch(Sleep.self, kids, sort: [NSSortDescriptor(key: "start", ascending: true)])
        let allWakes = fetch(NightWake.self, NSPredicate(format: "child.family == %@", family() ?? NSNull()))
        let sleepRows = sleeps.map { s in
            // Opvågninger i natten: antal og minutter vågen
            let ws = s.nap ? [] : allWakes.filter { w in
                w.child == s.child && (w.start.map { st in s.start.map { st >= $0 } ?? false } ?? false)
                    && (w.start.map { st in s.end.map { st <= $0 } ?? true } ?? false)
            }
            let awake = ws.reduce(0.0) { $0 + max(0, (($1.end ?? s.end ?? now).timeIntervalSince($1.start ?? now)) / 60) }
            return [name(s.child), stamp(s.start), stamp(s.end),
                    s.start.flatMap { a in s.end.map { String(Int($0.timeIntervalSince(a) / 60)) } } ?? "",
                    s.nap ? "Lur" : "Nat", ws.isEmpty ? "" : String(ws.count), ws.isEmpty ? "" : String(Int(awake.rounded()))]
        }

        let feeds = fetch(Feeding.self, kids, sort: [NSSortDescriptor(key: "time", ascending: true)])
        let feedRows = feeds.map { f in
            let kind = FeedKind(rawValue: f.kind ?? "")
            return [name(f.child), stamp(f.time), kind.map(FKLabels.feeding) ?? (f.kind ?? ""), num(f.amountMl),
                    kind == .bottle ? FKLabels.milk(Milk(rawValue: f.milk ?? "") ?? .breast) : "", f.note ?? ""]
        }

        let pumps = fetch(Pumping.self, fam, sort: [NSSortDescriptor(key: "time", ascending: true)])
        let pumpRows = pumps.map { p in
            [stamp(p.time), num(p.amountMl), p.side.flatMap { Side(rawValue: $0)?.label } ?? "", num(p.minutes)]
        }

        let growth = fetch(Growth.self, kids, sort: [NSSortDescriptor(key: "date", ascending: true)])
        let growthRows = growth.map { g in [name(g.child), date(g.date), num(g.weightKg), num(g.lengthCm), num(g.headCm)] }

        return [
            CSVFile(name: "folke-soevn-\(today).csv",
                    text: CSV.table(["Barn", "Start", "Slut", "Minutter", "Type", "Opvågninger", "Vågen (min)"], sleepRows), rows: sleepRows.count),
            CSVFile(name: "folke-mad-\(today).csv",
                    text: CSV.table(["Barn", "Tidspunkt", "Type", "Mængde (ml)", "Mælk", "Note"], feedRows), rows: feedRows.count),
            CSVFile(name: "folke-udpumpning-\(today).csv",
                    text: CSV.table(["Tidspunkt", "Mængde (ml)", "Side", "Minutter"], pumpRows), rows: pumpRows.count),
            CSVFile(name: "folke-vaekst-\(today).csv",
                    text: CSV.table(["Barn", "Dato", "Vægt (kg)", "Længde (cm)", "Hovedomfang (cm)"], growthRows),
                    rows: growthRows.count),
        ]
    }
}
