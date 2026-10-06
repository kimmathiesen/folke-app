import Foundation

public enum Sex: String, CaseIterable, Sendable {
    case boy, girl
}

/// Port af `who.py`: WHO-vækstkurver (2006) 0-24 mdr. med LMS-metoden.
public enum WHO {
    public enum Measure: String, CaseIterable, Sendable {
        case weight = "w", length = "l", head = "h"

        /// Gyldigt interval for en måling (som `RANGES` i app.py).
        public var range: ClosedRange<Double> {
            switch self {
            case .weight: 0.5...30
            case .length: 30...120
            case .head: 25...60
            }
        }
    }

    public enum Percentile: String, CaseIterable, Sendable {
        case p3, p15, p50, p85, p97

        public var z: Double {
            switch self {
            case .p3: -1.8808
            case .p15: -1.0364
            case .p50: 0
            case .p85: 1.0364
            case .p97: 1.8808
            }
        }
    }

    public struct CurveRow: Equatable, Sendable {
        public var month: Int
        public var values: [Percentile: Double]

        public subscript(_ p: Percentile) -> Double { values[p] ?? .nan }
    }

    /// L, M og S lineært interpoleret mellem hele måneder (klemt til 0-24).
    public static func lms(_ kind: Measure, _ sex: Sex, month m: Double) -> (l: Double, m: Double, s: Double) {
        let rows = lms[sex]![kind]!
        let m = min(max(m, 0), 24)
        let i = min(Int(m), 23)
        let f = m - Double(i)
        let a = rows[i], b = rows[i + 1]
        let v = (0..<3).map { a[$0] + (b[$0] - a[$0]) * f }
        return (v[0], v[1], v[2])
    }

    public static func value(_ kind: Measure, _ sex: Sex, month: Double, z: Double) -> Double {
        let (L, M, S) = lms(kind, sex, month: month)
        return L == 0 ? M * exp(S * z) : M * pow(1 + L * S * z, 1 / L)
    }

    /// z-værdien for en måling (hvor mange standardafvigelser fra medianen), eller nil uden for 0-24 mdr.
    public static func zScore(_ kind: Measure, _ sex: Sex, month: Double, value v: Double) -> Double? {
        guard month >= 0, month <= 24, v > 0 else { return nil }
        let (L, M, S) = lms(kind, sex, month: month)
        return L == 0 ? log(v / M) / S : (pow(v / M, L) - 1) / (L * S)
    }

    /// Omtrentlig percentil (1-99) for en måling, eller nil uden for 0-24 mdr.
    public static func percentile(_ kind: Measure, _ sex: Sex, month: Double, value v: Double?) -> Int? {
        guard let v, month >= 0, month <= 24 else { return nil }
        let (L, M, S) = lms(kind, sex, month: month)
        let z = L == 0 ? log(v / M) / S : (pow(v / M, L) - 1) / (L * S)
        let p = Int((50 * (1 + erf(z / 2.0.squareRoot()))).rounded(.toNearestOrEven))
        return max(1, min(99, p))
    }

    /// Kurverne P3-P97 for hver hel måned 0...upto, afrundet til to decimaler.
    public static func curves(_ kind: Measure, _ sex: Sex, upto: Int = 12) -> [CurveRow] {
        (0...upto).map { m in
            var values: [Percentile: Double] = [:]
            for p in Percentile.allCases {
                values[p] = (value(kind, sex, month: Double(m), z: p.z) * 100).rounded(.toNearestOrEven) / 100
            }
            return CurveRow(month: m, values: values)
        }
    }

    /// Alder i måneder ved en måling (som app.py: dage / 30,4375).
    public static func ageMonths(birthDate: Date, at date: Date, calendar: Calendar = .current) -> Double {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: birthDate),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        return Double(days) / 30.4375
    }

    /// Kurverne vises op til 12 mdr., til barnet er 9 mdr., derefter op til 24.
    public static func chartMonths(ageMonths: Double) -> Int {
        ageMonths < 9 ? 12 : 24
    }
}
