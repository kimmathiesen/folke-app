import FolkeCore
import SwiftUI

/// «Søvn i tal» (`#statistik` i index.html): de seneste 14 dage og ugen mod ugen før.
struct StatsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted
    @State private var stats: SleepStats?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                BackHeader(title: "Søvn i tal") { model.page = .home }
                if let s = stats {
                    VStack(alignment: .leading, spacing: 8) {
                        StatsChart(stats: s)
                        HStack(spacing: 16) {
                            legend("Nat", "#8b7cf6")
                            legend("Dag", "#a9c2ff")
                        }
                        Text(s.text ?? "Der er ikke registreret nok endnu. Når en hel dag med lure og nat er registreret, kommer tallene her.")
                            .font(.subheadline).foregroundStyle(Color.fg)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .card()
                    table(s).card().padding(.top, 16)
                    Text("Gennemsnit af de seneste 7 hele dage mod ugen før. Dage, hvor natten mangler, vises i grafen, men tæller ikke med i gennemsnittet.")
                        .font(.footnote).foregroundStyle(muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12).padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .contentMargins(.horizontal, 18, for: .scrollContent)
        .contentMargins(.bottom, 20, for: .scrollContent)
        .scrollIndicators(.hidden)
        .onAppear { stats = model.store.sleepStats() }
    }

    func legend(_ title: String, _ hex: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(Color(hex: hex)).frame(width: 10, height: 10)
            Text(title).font(.subheadline).foregroundStyle(muted)
        }
        .accessibilityHidden(true)
    }

    static func clock(_ m: Int?) -> String {
        guard let m else { return "–" }
        return String(format: "%02d.%02d", m / 60, m % 60)
    }

    static func number(_ v: Double?) -> String {
        guard let v else { return "–" }
        return v == v.rounded() ? "\(Int(v))" : Format.number(v)
    }

    static func duration(_ m: Int?) -> String { m.map { Format.duration(minutes: $0) } ?? "–" }

    /// Pil ved tydelig forskel: 10 min for klokkeslæt, 0,3 for antal, ellers 5 % (som index.html)
    static func arrow(_ a: Double?, _ b: Double?, kind: String) -> String {
        guard let a, let b else { return "" }
        let d = a - b
        let big = kind == "clock" ? abs(d) >= 10 : kind == "count" ? abs(d) >= 0.3 : abs(d) >= max(1, abs(b) * 0.05)
        return big ? (d > 0 ? " ↑" : " ↓") : ""
    }

    func table(_ s: SleepStats) -> some View {
        let w = s.week, p = s.prev
        typealias Row = (String, String, String, String)
        func dur(_ l: String, _ a: Int?, _ b: Int?) -> Row {
            (l, Self.duration(a), Self.duration(b), Self.arrow(a.map(Double.init), b.map(Double.init), kind: "min"))
        }
        func clk(_ l: String, _ a: Int?, _ b: Int?) -> Row {
            (l, Self.clock(a), Self.clock(b), Self.arrow(a.map(Double.init), b.map(Double.init), kind: "clock"))
        }
        func cnt(_ l: String, _ a: Double?, _ b: Double?) -> Row {
            (l, Self.number(a), Self.number(b), Self.arrow(a, b, kind: "count"))
        }
        var rows: [Row] = [dur("Søvn i døgnet", w.totalMin, p.totalMin), dur("Om natten", w.nightMin, p.nightMin),
                           dur("Om dagen", w.dayMin, p.dayMin), cnt("Lure pr. dag", w.naps, p.naps),
                           dur("Lurenes længde", w.napLen, p.napLen), clk("Sengetid", w.bed, p.bed),
                           clk("Vågnede", w.wake, p.wake)]
        if w.wakes != nil || p.wakes != nil { rows.append(cnt("Opvågninger pr. nat", w.wakes, p.wakes)) }
        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 0) {
            GridRow {
                Text("")
                Text("Seneste 7 dage").gridColumnAlignment(.trailing)
                Text("Ugen før").gridColumnAlignment(.trailing)
            }
            .font(.footnote).foregroundStyle(muted)
            .padding(.bottom, 6)
            ForEach(rows.indices, id: \.self) { i in
                let r = rows[i]
                Rectangle().fill(Color.line).frame(height: 1).gridCellColumns(3)
                GridRow {
                    Text(r.0).foregroundStyle(Color.fg)
                    (Text(r.1).foregroundStyle(Color.fg) + Text(r.3).font(.caption).foregroundStyle(muted))
                        .monospacedDigit()
                    Text(r.2).foregroundStyle(muted).monospacedDigit()
                }
                .font(.subheadline)
                .padding(.vertical, 9)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(r.0): \(r.1), ugen før \(r.2)")
            }
        }
    }
}

/// Søjler for de seneste 14 dage: nat nederst, dag ovenpå (`#ssvg`). «?» over en dag, hvor natten mangler.
struct StatsChart: View {
    var stats: SleepStats
    @Environment(\.muted) private var muted

    var body: some View {
        Canvas { ctx, size in
            let k = size.width / 340
            ctx.scaleBy(x: k, y: k)
            let D = stats.days, n = D.count
            guard n > 0 else { return }
            let W = 340.0, H = 200.0, L = 34.0, R = 6.0, T = 26.0, B = 26.0, bw = (W - L - R) / Double(n)
            let mx = max(12, D.map { Double(($0.nightMin ?? 0) + $0.dayMin) / 60 }.max() ?? 0)
            let top = (mx / 4).rounded(.up) * 4
            let sy = { (v: Double) in H - B - (H - T - B) * v / top }
            func label(_ s: String, _ x: Double, _ y: Double, _ anchor: UnitPoint) {
                ctx.draw(Text(s).font(.caption2).foregroundStyle(muted), at: CGPoint(x: x, y: y), anchor: anchor)
            }
            var v = 0.0
            while v <= top {
                var p = Path()
                p.move(to: CGPoint(x: L, y: sy(v)))
                p.addLine(to: CGPoint(x: W - R, y: sy(v)))
                ctx.stroke(p, with: .color(.white.opacity(0.07)), lineWidth: 1)
                label("\(Int(v))", L - 6, sy(v), .trailing)
                v += 4
            }
            for (i, d) in D.enumerated() {
                let x = L + Double(i) * bw, nt = Double(d.nightMin ?? 0) / 60, dy = Double(d.dayMin) / 60
                if nt > 0 {
                    let r = CGRect(x: x + bw * 0.18, y: sy(nt), width: bw * 0.64, height: sy(0) - sy(nt))
                    ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(Color(hex: "#8b7cf6")))
                }
                if dy > 0 {
                    let r = CGRect(x: x + bw * 0.18, y: sy(nt + dy), width: bw * 0.64, height: sy(nt) - sy(nt + dy))
                    ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(Color(hex: "#a9c2ff")))
                }
                if d.registered && d.nightMin == nil { label("?", x + bw / 2, sy(dy) - 8, .center) }
                if i % 2 == (n - 1) % 2 {
                    label("\(Calendar.current.component(.day, from: d.date)).", x + bw / 2, H - 12, .center)
                }
            }
            label("timer", L - 6, 6, .trailing)
        }
        .aspectRatio(340 / 200, contentMode: .fit)
        .dynamicTypeSize(...DynamicTypeSize.large) // tegning med fast plads til aksetallene
        .accessibilityElement()
        .accessibilityLabel("Søvn de seneste 14 dage")
        .accessibilityValue(stats.days.compactMap { d in
            d.totalMin.map { "\(Calendar.current.component(.day, from: d.date)).: \(Format.duration(minutes: $0))" }
        }.joined(separator: ", "))
    }
}
