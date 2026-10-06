import FolkeCore
import SwiftUI

/// Ringen: 24 timer, midnat i bunden og middag i toppen (som `#dial` i index.html, viewBox 360×400).
struct DialView: View {
    var snapshot: Snapshot
    var now: Date
    var calendar: Calendar = .current

    static let size = CGSize(width: 360, height: 400)
    static let center = CGPoint(x: 180, y: 200)

    @Environment(\.muted) private var muted
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func point(_ r: Double, _ t: Double) -> CGPoint {
        let a = (90 + t * 15) * .pi / 180
        return CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
    }

    static func arc(_ r: Double, _ a: Double, _ b: Double) -> Path {
        var p = Path()
        p.addArc(center: center, radius: r, startAngle: .degrees(90 + a * 15), endAngle: .degrees(90 + b * 15),
                 clockwise: false)
        return p
    }

    func hour(_ d: Date) -> Double { Theme.hour(of: d, calendar: calendar) }

    /// Start på ringen: klokkeslættet, eller midnat, hvis søvnen startede i går.
    func from(_ d: Date) -> Double {
        calendar.isDate(d, inSameDayAs: now) ? hour(d) : 0
    }

    var body: some View {
        GeometryReader { g in
            let k = g.size.width / Self.size.width
            ZStack {
                Canvas { ctx, _ in
                    ctx.scaleBy(x: k, y: k)
                    drawStatic(&ctx)
                    drawDynamic(&ctx)
                }
                if let r = snapshot.running {
                    // Kørende søvn pulserer
                    Canvas { ctx, _ in
                        ctx.scaleBy(x: k, y: k)
                        let a = from(r.start), b = hour(now)
                        if b > a {
                            ctx.stroke(Self.arc(88, a, b), with: .color(Color(Theme.night)),
                                       style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        }
                    }
                    .opacity(pulse ? 0.35 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
                    .onDisappear { pulse = false }
                }
                labels(k)
                middle(k)
            }
        }
        .aspectRatio(Self.size, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dagens rytme")
    }

    func drawStatic(_ ctx: inout GraphicsContext) {
        ctx.stroke(Path(ellipseIn: CGRect(x: 92, y: 112, width: 176, height: 176)),
                   with: .color(.white.opacity(0.06)), lineWidth: 9)
        // Yderste ring i døgnets farver, 96 kvarterer
        for i in 0..<96 {
            let a = Double(i) / 4, b = min(24, Double(i + 1) / 4 + 0.02)
            ctx.stroke(Self.arc(105, a, b), with: .color(Color(Theme.ringColor(hour: a + 0.125))), lineWidth: 14)
        }
        for t in [0.0, 6, 12, 18] {
            let p = Self.point(105, t)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)),
                     with: .color(.white.opacity(0.85)))
        }
    }

    func drawDynamic(_ ctx: inout GraphicsContext) {
        for x in snapshot.today {
            let a = from(x.start), b = hour(x.end)
            if b > a {
                ctx.stroke(Self.arc(88, a, b), with: .color(Color(x.nap ? Theme.nap : Theme.night)),
                           style: StrokeStyle(lineWidth: 9, lineCap: .round))
            }
        }
        // Planlagte lure resten af dagen som stiplede buer
        for x in snapshot.plan?.items ?? [] where x.kind == .nap && calendar.isDate(x.start, inSameDayAs: now) {
            let a = hour(x.start)
            let b = x.end.map { calendar.isDate($0, inSameDayAs: now) ? hour($0) : 24 } ?? 24
            if b > a {
                ctx.stroke(Self.arc(88, a, b), with: .color(Color(Theme.nap, opacity: 0.45)),
                           style: StrokeStyle(lineWidth: 9, lineCap: .round, dash: [2, 6]))
            }
        }
        if let nx = snapshot.next(at: now) {
            let c = Self.point(88, hour(nx.now ? now : nx.time))
            let r = CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)
            ctx.fill(Path(ellipseIn: r), with: .color(Color(hex: "#0f1830")))
            ctx.stroke(Path(ellipseIn: r), with: .color(.fg), style: StrokeStyle(lineWidth: 1.6, dash: [3, 2.5]))
        }
        let n = Self.point(105, hour(now))
        ctx.fill(Path(ellipseIn: CGRect(x: n.x - 13, y: n.y - 13, width: 26, height: 26)), with: .color(.white.opacity(0.22)))
        ctx.fill(Path(ellipseIn: CGRect(x: n.x - 7.5, y: n.y - 7.5, width: 15, height: 15)), with: .color(.white))
    }

    /// Klokkeslæt og navne ved 12, 6, 18 og 0.
    func labels(_ k: Double) -> some View {
        let items: [(String, String, String, Color, CGPoint)] = [
            ("sun.max", "12:00", "Middag", Color(hex: "#ffd27a"), CGPoint(x: 180, y: 22)),
            ("sunrise", "06:00", "Morgen", Color(hex: "#f2c96b"), CGPoint(x: 34, y: 176)),
            ("sunset", "18:00", "Aften", Color(hex: "#f08a5a"), CGPoint(x: 326, y: 176)),
            ("moon", "00:00", "Nat", Color(hex: "#9d8cf8"), CGPoint(x: 180, y: 334)),
        ]
        return ForEach(items, id: \.1) { icon, time, name, color, p in
            VStack(spacing: 2 * k) {
                Image(systemName: icon)
                    .font(.system(size: 17 * k, weight: .light))
                    .foregroundStyle(color)
                    .frame(height: 24 * k)
                Text(time).font(.system(size: 15 * k, weight: .semibold)).foregroundStyle(Color.fg)
                Text(name).font(.system(size: 13 * k)).foregroundStyle(muted)
            }
            .fixedSize()
            .position(x: p.x * k, y: (p.y + 26) * k)
        }
    }

    /// Øverst i midten: hvornår han faldt i søvn, eller næste lur/sengetid (som `#nowt` i index.html).
    var headline: String {
        if let r = snapshot.running { return "Faldt i søvn kl. \(Format.time(r.start, calendar: calendar))" }
        guard let n = snapshot.next(at: now) else { return "" }
        if n.now { return "Næste lur: nu" }
        return "\(n.kind == .nap ? "Næste lur" : "Sengetid") kl. \(Format.time(n.time, calendar: calendar))"
    }

    /// I midten: næste lur/sengetid, tæller og tilstand.
    func middle(_ k: Double) -> some View {
        let since = snapshot.running?.start ?? snapshot.awakeSince
        return VStack(spacing: 2) {
            Text(headline).font(.system(size: 14)).foregroundStyle(muted)
            Text(since.map { Format.counter(seconds: Int(now.timeIntervalSince($0))) } ?? "--")
                .font(.system(size: min(34, 30 * k), weight: .light))
                .monospacedDigit()
                .foregroundStyle(Color.fg)
            Text(snapshot.running != nil ? "Sover" : "Vågen").font(.system(size: 14)).foregroundStyle(muted)
        }
        .position(x: Self.center.x * k, y: Self.center.y * k)
    }
}
