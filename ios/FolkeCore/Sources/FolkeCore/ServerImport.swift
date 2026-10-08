import CoreData
import Foundation

/// Import fra den gamle Folke-server (`GET /api/export`, PLAN.md afsnit 8). Kun til familiens egne builds:
/// andre brugere har ingen server. Serverens id bruges som nøgle (`serverID`), så gentaget import ikke giver dubletter.
public struct ServerImportResult: Equatable, Sendable {
    public var sleeps = 0
    public var feedings = 0
    public var pumpings = 0
    public var growth = 0
    public var wakes = 0
    public var createdChild = false
    public var runningSleep = false

    public var summary: String {
        "Importeret: \(sleeps) søvn, \(feedings) måltider, \(pumpings) udpumpninger, \(growth) vækstmålinger"
            + (runningSleep ? " og en søvn i gang" : "")
    }
}

public enum ServerImportError: Error, LocalizedError {
    case notAnExport
    case noChild

    public var errorDescription: String? {
        switch self {
        case .notAnExport: "Filen er ikke en eksport fra Folke-serveren"
        case .noChild: "Eksporten indeholder intet barn"
        }
    }
}

struct ServerExport: Decodable {
    struct Child: Decodable { var id: Int; var first_name: String?; var birth_date: String }
    struct Sleep: Decodable { var id: Int; var start: String; var end: String; var nap: Int? }
    struct Timer: Decodable { var id: Int; var start: String }
    struct Feeding: Decodable {
        var id: Int; var start: String; var type: String?; var method: String?; var amount: Double?; var notes: String?
    }
    struct Pumping: Decodable { var id: Int; var start: String; var amount: Double?; var side: String?; var minutes: Double? }
    struct Growth: Decodable { var id: Int; var date: String; var w: Double?; var l: Double?; var h: Double? }
    struct Wake: Decodable { var id: Int; var start: String; var end: String? }
    struct Prefs: Decodable {
        struct Features: Decodable { var breast: Bool?; var solids: Bool?; var pump: Bool? }
        var features: Features?
        var sex: String?
        var pump_remind: Double?
        var child_name: String?
    }

    var child: [Child]
    var sleep: [Sleep]?
    var timer: [Timer]?
    var feeding: [Feeding]?
    var pumping: [Pumping]?
    var growth: [Growth]?
    var night_wake: [Wake]?
    var prefs: Prefs?
}

public extension FolkeStore {
    /// Importér en eksport. Findes barnet ikke, oprettes det med navn, fødselsdato, køn og funktionsvalg fra serveren.
    /// Rækker, der allerede er importeret (samme serverID), opdateres i stedet for at blive kopieret.
    @discardableResult
    func importServerExport(_ data: Data) throws -> ServerImportResult {
        let e: ServerExport
        do {
            e = try JSONDecoder().decode(ServerExport.self, from: data)
        } catch {
            throw ServerImportError.notAnExport
        }
        guard let sc = e.child.first, let birth = Self.day(sc.birth_date) else { throw ServerImportError.noChild }
        var r = ServerImportResult()

        if child() == nil {
            let name = [e.prefs?.child_name, sc.first_name].compactMap { $0 }.first { !$0.isEmpty } ?? "Barnet"
            try createChild(name: name, birthDate: birth, sex: Sex(rawValue: e.prefs?.sex ?? "") ?? .boy)
            if let s = settings(), let f = family(), let p = e.prefs {
                s.featureBreast = p.features?.breast ?? s.featureBreast
                s.featureSolids = p.features?.solids ?? s.featureSolids
                f.featurePump = p.features?.pump ?? f.featurePump
                f.pumpRemindHours = p.pump_remind ?? f.pumpRemindHours
            }
            r.createdChild = true
        }
        let c = child()
        let fam = family()

        // Serverens id er nøglen: pr. barn for søvn, mad og vækst, pr. familie for udpumpning
        func existing<T: NSManagedObject>(_ type: T.Type, _ id: Int) -> T? {
            let p = NSPredicate(format: "serverID == %lld", Int64(id))
            return fetch(type, type == Pumping.self ? forFamily(p) : forChild(p), limit: 1).first
        }

        for s in e.sleep ?? [] {
            guard let start = Self.time(s.start), let end = Self.time(s.end) else { continue }
            let o = existing(FolkeCore.Sleep.self, s.id) ?? {
                let n = insert(FolkeCore.Sleep.self, child: c)
                n.id = UUID()
                n.serverID = Int64(s.id)
                n.child = c
                return n
            }()
            o.start = start
            o.end = end
            o.nap = (s.nap ?? 1) != 0
            r.sleeps += 1
        }

        // En kørende timer bliver til en søvn uden slut, kun én gang (serverID = -timer-id) og kun hvis ingen søvn er i gang
        if let t = e.timer?.first, let start = Self.time(t.start), runningSleep() == nil,
           existing(FolkeCore.Sleep.self, -t.id) == nil {
            let n = insert(FolkeCore.Sleep.self, child: c)
            n.id = UUID()
            n.serverID = Int64(-t.id)
            n.start = start
            n.nap = Predictor.napGuess(start, calendar: calendar)
            n.child = c
            r.runningSleep = true
        }

        for f in e.feeding ?? [] {
            guard let t = Self.time(f.start) else { continue }
            let kind: FeedKind
            switch (f.method ?? "", f.type ?? "") {
            case ("left breast", _): kind = .left
            case ("right breast", _): kind = .right
            case ("both breasts", _): kind = .both
            case ("bottle", _): kind = .bottle
            case (_, "solid food"), ("parent fed", _): kind = .solid
            default: continue
            }
            let o = existing(Feeding.self, f.id) ?? {
                let n = insert(Feeding.self, child: c)
                n.id = UUID()
                n.serverID = Int64(f.id)
                n.child = c
                return n
            }()
            o.time = t
            o.kind = kind.rawValue
            o.amountMl = kind == .bottle ? (f.amount ?? 0) : 0
            o.milk = kind == .bottle ? (f.type == "formula" ? Milk.formula : .breast).rawValue : nil
            o.note = kind == .solid ? f.notes.flatMap { $0.isEmpty ? nil : $0 } : nil
            r.feedings += 1
        }

        for p in e.pumping ?? [] {
            guard let t = Self.time(p.start), let ml = p.amount, ml > 0 else { continue }
            let o = existing(Pumping.self, p.id) ?? {
                let n = insert(Pumping.self, child: c)
                n.id = UUID()
                n.serverID = Int64(p.id)
                n.family = fam
                return n
            }()
            o.time = t
            o.amountMl = ml
            o.side = p.side.flatMap { Side(rawValue: $0)?.rawValue }
            o.minutes = p.minutes ?? 0
            r.pumpings += 1
        }

        for g in e.growth ?? [] {
            guard let d = Self.day(g.date), g.w != nil || g.l != nil || g.h != nil else { continue }
            let o = existing(Growth.self, g.id) ?? {
                let n = insert(Growth.self, child: c)
                n.id = UUID()
                n.serverID = Int64(g.id)
                n.child = c
                return n
            }()
            o.date = calendar.startOfDay(for: d)
            o.weightKg = g.w ?? 0
            o.lengthCm = g.l ?? 0
            o.headCm = g.h ?? 0
            r.growth += 1
        }

        // Opvågninger om natten: genkendes på starttidspunktet (de har intet serverID)
        for w in e.night_wake ?? [] {
            guard let st = Self.time(w.start) else { continue }
            let o = fetch(NightWake.self, forChild(NSPredicate(format: "start == %@", st as NSDate)), limit: 1).first ?? {
                let n = insert(NightWake.self, child: c)
                n.id = UUID()
                n.start = st
                n.child = c
                return n
            }()
            o.end = w.end.flatMap(Self.time)
            r.wakes += 1
        }

        try save()
        return r
    }

    /// ISO-tid fra serveren, fx "2026-10-04T15:44:51+00:00" (med eller uden brøkdele af sekunder).
    static func time(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    /// "2026-06-20" som lokal dato (kl. 12, så tidszonen ikke flytter dagen)
    static func day(_ s: String) -> Date? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        var c = Calendar.current
        c.timeZone = .current
        return c.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }
}
