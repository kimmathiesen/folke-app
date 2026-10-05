import CoreData
import Foundation

// MARK: Vækst (port af /api/growth i app.py)

public enum GrowthError: Error, Equatable, LocalizedError {
    case inFuture
    case outOfRange(WHO.Measure)
    case empty

    public var errorDescription: String? {
        switch self {
        case .inFuture: "Datoen ligger i fremtiden"
        case .outOfRange(let m): "\(m.name) skal være mellem \(Format.number(m.range.lowerBound)) og \(Format.number(m.range.upperBound))"
        case .empty: "Skriv mindst én måling"
        }
    }
}

public extension WHO.Measure {
    var name: String {
        switch self {
        case .weight: "Vægt"
        case .length: "Længde"
        case .head: "Hovedomfang"
        }
    }

    /// Kort navn til fanerne
    var tab: String { self == .head ? "Hoved" : name }

    var unit: String { self == .weight ? "kg" : "cm" }
}

/// En måling med alder og percentiler (som `entries` fra `/api/growth`).
public struct GrowthPoint: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    /// Alder i måneder, afrundet til 2 decimaler
    public var months: Double
    public var values: [WHO.Measure: Double]
    public var percentiles: [WHO.Measure: Int]
}

public extension Format {
    /// Tal med dansk komma og højst 2 decimaler («6,4»).
    static func number(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "da_DK")).grouping(.never))
    }
}

public extension FolkeStore {
    /// Gem en ny måling eller ret en eksisterende. Mindst én af de tre, inden for grænserne, dato ikke i fremtiden.
    @discardableResult
    func saveGrowth(_ existing: Growth? = nil, date: Date, values: [WHO.Measure: Double?], now: Date = .now) throws -> Growth {
        let day = calendar.startOfDay(for: date)
        if day > calendar.startOfDay(for: now) { throw GrowthError.inFuture }
        for m in WHO.Measure.allCases {
            if let v = values[m] ?? nil, !m.range.contains(v) { throw GrowthError.outOfRange(m) }
        }
        if WHO.Measure.allCases.allSatisfy({ (values[$0] ?? nil) == nil }) { throw GrowthError.empty }
        let c = child()
        let g = existing ?? insert(Growth.self, child: c)
        if existing == nil {
            g.id = UUID()
            g.child = c
        }
        g.date = day
        g.weightKg = (values[.weight] ?? nil) ?? 0
        g.lengthCm = (values[.length] ?? nil) ?? 0
        g.headCm = (values[.head] ?? nil) ?? 0
        try save()
        return g
    }

    func growth(id: UUID) -> Growth? {
        fetch(Growth.self, NSPredicate(format: "id == %@", id as CVarArg), limit: 1).first
    }

    /// Alle målinger, ældste først, med alder og percentil efter barnets køn.
    func growthPoints() -> [GrowthPoint] {
        guard let c = child(), let birth = c.birthDate else { return [] }
        let sex = Sex(rawValue: c.sex ?? "") ?? .boy
        return fetch(Growth.self, sort: [NSSortDescriptor(key: "date", ascending: true)]).compactMap { g in
            guard let id = g.id, let date = g.date else { return nil }
            let m = (WHO.ageMonths(birthDate: birth, at: date, calendar: calendar) * 100).rounded(.toNearestOrEven) / 100
            var values: [WHO.Measure: Double] = [:]
            var pct: [WHO.Measure: Int] = [:]
            for (k, v) in [(WHO.Measure.weight, g.weightKg), (.length, g.lengthCm), (.head, g.headCm)] where v > 0 {
                values[k] = v
                pct[k] = WHO.percentile(k, sex, month: m, value: v)
            }
            return GrowthPoint(id: id, date: date, months: m, values: values, percentiles: pct)
        }
    }
}

// MARK: Udpumpningshistorik (port af /api/pump/history i app.py)

public struct PumpDay: Equatable, Sendable {
    public var date: Date
    public var ml: Int
    public var count: Int

    public init(date: Date, ml: Int, count: Int) {
        self.date = date
        self.ml = ml
        self.count = count
    }
}

public struct PumpHistory: Equatable, Sendable {
    /// Ældste først, i dag sidst
    public var days: [PumpDay]
    /// Gennemsnit af hele dage med udpumpning (i dag tæller ikke med)
    public var avgMl: Int?

    public init(days: [PumpDay], avgMl: Int?) {
        self.days = days
        self.avgMl = avgMl
    }
}

public extension FolkeStore {
    func pumpHistory(days n: Int = 14, now: Date = .now) -> PumpHistory {
        let today = calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .day, value: -(n - 1), to: today)!
        var ml = [Double](repeating: 0, count: n)
        var count = [Int](repeating: 0, count: n)
        for p in pumpings(since: first) {
            guard let t = p.time,
                  let i = calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: t)).day,
                  (0..<n).contains(i) else { continue }
            ml[i] += p.amountMl
            count[i] += 1
        }
        let days = (0..<n).map { i in
            PumpDay(date: calendar.date(byAdding: .day, value: i, to: first)!,
                    ml: Int(ml[i].rounded(.toNearestOrEven)), count: count[i])
        }
        let full = days.dropLast().filter { $0.count > 0 }.map(\.ml)
        let avg = full.isEmpty ? nil : Int((Double(full.reduce(0, +)) / Double(full.count)).rounded(.toNearestOrEven))
        return PumpHistory(days: days, avgMl: avg)
    }

    func pumping(id: UUID) -> Pumping? {
        fetch(Pumping.self, NSPredicate(format: "id == %@", id as CVarArg), limit: 1).first
    }
}

public extension Format {
    /// «150 ml · begge · 15 min» (som `pdesc` i index.html).
    static func pumpDescription(amountMl: Double, side: Side?, minutes: Double) -> String {
        ["\(Int(amountMl.rounded())) ml", side?.label, minutes > 0 ? "\(Int(minutes.rounded())) min" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// «3 timer» / «2½ timer»
    static func hours(_ h: Double) -> String {
        number(h).replacingOccurrences(of: ",5", with: "½")
    }
}
