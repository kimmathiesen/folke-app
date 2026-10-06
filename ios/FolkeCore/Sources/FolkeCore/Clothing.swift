import Foundation

/// Skøn over tøjstørrelse (PLAN.md afsnit 5, Vækst): sidste længdemåling fremskrives langs sin egen percentil
/// på WHO-kurven til i dag. Kun et skøn: størrelser varierer mellem mærker.
public struct ClothingEstimate: Equatable, Sendable {
    /// Skønnet længde i dag (cm)
    public var lengthToday: Double
    /// Den mindste størrelse, der er mindst lige så lang som barnet
    public var size: Int
    /// Næste størrelse, og hvornår den skønnes at passe
    public var nextSize: Int?
    public var nextSizeFrom: Date?
    /// Målingen, skønnet bygger på
    public var measuredAt: Date
    public var percentile: Int?
}

public enum Clothing {
    /// Danske babystørrelser (cm)
    public static let sizes = [44, 50, 56, 62, 68, 74, 80, 86, 92, 98]

    public static func size(forLength cm: Double) -> Int? {
        sizes.first { Double($0) >= cm }
    }

    public static func estimate(length: Double, measuredAt: Date, birthDate: Date, sex: Sex, now: Date,
                                calendar: Calendar = .current) -> ClothingEstimate? {
        let m0 = WHO.ageMonths(birthDate: birthDate, at: measuredAt, calendar: calendar)
        let mNow = WHO.ageMonths(birthDate: birthDate, at: now, calendar: calendar)
        guard mNow <= 24, let z = WHO.zScore(.length, sex, month: m0, value: length) else { return nil }
        let today = WHO.value(.length, sex, month: max(mNow, m0), z: z)
        guard let size = size(forLength: today) else { return nil }
        var next: Int?, from: Date?
        if let i = sizes.firstIndex(of: size), i + 1 < sizes.count {
            // Første dag, hvor den fremskrevne længde er over den nuværende størrelse
            let start = calendar.startOfDay(for: now)
            for d in 1...800 {
                guard let day = calendar.date(byAdding: .day, value: d, to: start) else { break }
                let m = WHO.ageMonths(birthDate: birthDate, at: day, calendar: calendar)
                if m > 24 { break }
                if WHO.value(.length, sex, month: m, z: z) > Double(size) {
                    next = sizes[i + 1]
                    from = day
                    break
                }
            }
        }
        return ClothingEstimate(lengthToday: today, size: size, nextSize: next, nextSizeFrom: from, measuredAt: measuredAt,
                                percentile: WHO.percentile(.length, sex, month: m0, value: length))
    }
}

public extension FolkeStore {
    /// Skøn ud fra den seneste længdemåling (nil uden måling eller efter 24 mdr.).
    func clothingEstimate(now: Date = .now) -> ClothingEstimate? {
        guard let c = child(), let birth = c.birthDate,
              let last = growthPoints().last(where: { $0.values[.length] != nil }), let l = last.values[.length] else { return nil }
        return Clothing.estimate(length: l, measuredAt: last.date, birthDate: birth, sex: Sex(rawValue: c.sex ?? "") ?? .boy,
                                 now: now, calendar: calendar)
    }
}

public extension Format {
    /// «om ca. 5 uger», «om ca. 4 dage», «nu»
    static func untilText(_ d: Date, now: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: d)).day ?? 0
        if days <= 0 { return "nu" }
        if days < 14 { return "om ca. \(days) \(days == 1 ? "dag" : "dage")" }
        let weeks = Int((Double(days) / 7).rounded())
        return "om ca. \(weeks) uger"
    }
}
