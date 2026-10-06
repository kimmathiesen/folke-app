import Foundation

public struct RGB: Equatable, Sendable {
    public var r: Double, g: Double, b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    func mix(_ o: RGB, _ f: Double) -> RGB {
        RGB(r + (o.r - r) * f, g + (o.g - g) * f, b + (o.b - b) * f)
    }

    /// "#a9c2ff"
    public init(hex: String) {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(Double(v >> 16 & 0xff), Double(v >> 8 & 0xff), Double(v & 0xff))
    }
}

/// Farver fra index.html på branchen `standalone` (tabellerne `ST` og `SKY`), værdier 0-255.
public enum Theme {
    /// Ringens farve gennem døgnet.
    public static let ring: [(hour: Double, color: RGB)] = [
        (0, RGB(90, 75, 214)), (5, RGB(79, 111, 224)), (7.5, RGB(107, 181, 240)), (9.5, RGB(242, 201, 107)),
        (12, RGB(255, 214, 125)), (15, RGB(245, 178, 90)), (18, RGB(240, 138, 90)), (20.5, RGB(181, 111, 208)),
        (22.5, RGB(124, 111, 240)), (24, RGB(90, 75, 214)),
    ]

    public struct Sky: Equatable, Sendable {
        public var top: RGB
        public var bottom: RGB
        /// Styrken af skæret i ringens farve øverst.
        public var glow: Double
        /// Alfa for dæmpet tekst.
        public var muted: Double
    }

    /// Baggrunden gennem døgnet.
    public static let sky: [(hour: Double, sky: Sky)] = [
        (0, Sky(top: RGB(15, 24, 48), bottom: RGB(10, 16, 34), glow: 0.28, muted: 0.62)),
        (5, Sky(top: RGB(22, 34, 72), bottom: RGB(12, 20, 44), glow: 0.3, muted: 0.62)),
        (7.5, Sky(top: RGB(52, 84, 146), bottom: RGB(28, 46, 94), glow: 0.4, muted: 0.72)),
        (9.5, Sky(top: RGB(70, 112, 180), bottom: RGB(38, 68, 128), glow: 0.42, muted: 0.8)),
        (12, Sky(top: RGB(76, 124, 196), bottom: RGB(42, 79, 143), glow: 0.4, muted: 0.82)),
        (15, Sky(top: RGB(72, 116, 186), bottom: RGB(40, 74, 136), glow: 0.42, muted: 0.8)),
        (18, Sky(top: RGB(84, 86, 150), bottom: RGB(42, 44, 96), glow: 0.45, muted: 0.74)),
        (20.5, Sky(top: RGB(44, 40, 98), bottom: RGB(22, 24, 58), glow: 0.35, muted: 0.66)),
        (22.5, Sky(top: RGB(22, 28, 66), bottom: RGB(12, 17, 40), glow: 0.3, muted: 0.62)),
        (24, Sky(top: RGB(15, 24, 48), bottom: RGB(10, 16, 34), glow: 0.28, muted: 0.62)),
    ]

    public static let nap = RGB(hex: "#a9c2ff")
    public static let night = RGB(hex: "#8b7cf6")
    public static let boardColors = ["#f4f1ea", "#ff8fa3", "#ffd27a", "#8fb0ff"]

    static func segment<T>(_ table: [(Double, T)], _ t: Double) -> (T, T, Double) {
        let t = min(max(t, 0), 24)
        for i in 1..<table.count where t <= table[i].0 {
            let a = table[i - 1], b = table[i]
            return (a.1, b.1, (t - a.0) / (b.0 - a.0))
        }
        return (table[0].1, table[0].1, 0)
    }

    public static func ringColor(hour t: Double) -> RGB {
        let (a, b, f) = segment(ring.map { ($0.hour, $0.color) }, t)
        return a.mix(b, f)
    }

    public static func sky(hour t: Double) -> Sky {
        let (a, b, f) = segment(sky.map { ($0.hour, $0.sky) }, t)
        return Sky(top: a.top.mix(b.top, f), bottom: a.bottom.mix(b.bottom, f),
                   glow: a.glow + (b.glow - a.glow) * f, muted: a.muted + (b.muted - a.muted) * f)
    }

    /// Timer efter midnat som decimaltal (fx 13,5 for 13:30).
    public static func hour(of d: Date, calendar: Calendar = .current) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: d)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
    }
}
