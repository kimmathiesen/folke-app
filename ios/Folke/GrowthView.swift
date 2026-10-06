import FolkeCore
import SwiftUI

/// «Vækst» (`#v-growth` i index.html): WHO-kurver, seneste måling med percentil, liste og ret/slet.
struct GrowthView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted
    @State private var kind: WHO.Measure? = .weight
    @State private var editing: Editing?

    struct Editing: Identifiable {
        var point: GrowthPoint?
        var id: UUID { point?.id ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")! }
    }

    var body: some View {
        let s = model.snapshot
        let k = kind ?? .weight
        let age = s.birthDate.map { WHO.ageMonths(birthDate: $0, at: .now) } ?? 0
        let curves = WHO.curves(k, s.sex, upto: WHO.chartMonths(ageMonths: age))
        let points = s.growth.filter { $0.values[k] != nil }
        ScrollView {
            VStack(spacing: 0) {
                BackHeader(title: "Vækst") { model.page = .home }
                Segmented(options: WHO.Measure.allCases.map { ($0, $0.tab) }, selection: $kind)
                VStack(alignment: .leading, spacing: 8) {
                    GrowthChart(kind: k, curves: curves, points: points)
                    summary(points.last, k)
                }
                .card()
                .padding(.top, 16)
                if model.role == .far, let c = s.clothing {
                    ClothingCard(estimate: c, name: s.childName)
                }
                GoButton(title: "Tilføj måling") { editing = Editing(point: nil) }.padding(.top, 14)
                if !s.growth.isEmpty {
                    list(s.growth.reversed())
                }
                Text("\(s.sex == .boy ? "Drengekurver" : "Pigekurver") fra WHO (2006), som Sundhedsstyrelsen anbefaler til børn 0-5 år. Båndene viser 3.-97. percentil, og den stiplede linje er midten. Vejninger kan afvige mellem forskellige vægte, og én måling siger ikke alt. Tal med sundhedsplejersken, hvis du er i tvivl. Skift kurver under Indstillinger.")
                    .font(.system(size: 13)).foregroundStyle(muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16).padding(.horizontal, 4)
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .contentMargins(.horizontal, 18, for: .scrollContent)
        .contentMargins(.bottom, 28, for: .scrollContent)
        .sheet(item: $editing) { e in GrowthSheet(point: e.point) }
    }

    func summary(_ e: GrowthPoint?, _ k: WHO.Measure) -> some View {
        Group {
            if let e, let v = e.values[k] {
                (Text("\(k.tab): \(Format.number(v)) \(k.unit)").fontWeight(.medium).foregroundStyle(Color.fg)
                 + Text(" · \(e.date.formatted(.dateTime.day().month(.abbreviated).year())) · \(Format.number(e.months)) mdr."
                        + (e.percentiles[k].map { " · ca. \($0). percentil" } ?? ""))
                    .foregroundStyle(muted))
            } else {
                Text("Ingen målinger endnu").foregroundStyle(muted)
            }
        }
        .font(.system(size: 15))
    }

    func list(_ entries: [GrowthPoint]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                Button { editing = Editing(point: e) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(e.date.formatted(.dateTime.day().month(.abbreviated).year()))
                                .font(.system(size: 17)).foregroundStyle(Color.fg)
                            Text(WHO.Measure.allCases.compactMap { m in e.values[m].map { "\(Format.number($0)) \(m.unit)" } }
                                    .joined(separator: " · "))
                                .font(.system(size: 14)).foregroundStyle(muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(muted)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Color.line).frame(height: 1) } }
                }
                .buttonStyle(.plain)
            }
        }
        .card()
        .padding(.top, 16)
    }
}

/// Kurverne P3-P97 som bånd, P50 stiplet og målingerne i gult (som `drawG` i index.html, viewBox 340×262).
struct GrowthChart: View {
    var kind: WHO.Measure
    var curves: [WHO.CurveRow]
    var points: [GrowthPoint]
    @Environment(\.muted) private var muted

    var body: some View {
        Canvas { ctx, size in
            let k = size.width / 340
            ctx.scaleBy(x: k, y: k)
            let X = Double(curves.count - 1)
            let vals = curves.map { $0[.p3] } + curves.map { $0[.p97] } + points.compactMap { $0.values[kind] }
            let lo = vals.min() ?? 0, hi = vals.max() ?? 1, pd = (hi - lo) * 0.05, y0 = lo - pd, y1 = hi + pd
            let W = 340.0, H = 262.0, L = 40.0, R = 10.0, T = 22.0, B = 38.0
            let sx = { (m: Double) in L + (W - L - R) * m / X }
            let sy = { (v: Double) in H - B - (H - T - B) * (v - y0) / (y1 - y0) }
            func label(_ s: String, _ x: Double, _ y: Double, _ anchor: UnitPoint) {
                ctx.draw(Text(s).font(.system(size: 11)).foregroundStyle(muted), at: CGPoint(x: x, y: y), anchor: anchor)
            }

            // Vandrette linjer med tal
            let st = [0.5, 1, 2, 5, 10, 20].first { (y1 - y0) / $0 <= 6 } ?? 20
            var v = (y0 / st).rounded(.up) * st
            while v <= y1 {
                var p = Path()
                p.move(to: CGPoint(x: L, y: sy(v)))
                p.addLine(to: CGPoint(x: W - R, y: sy(v)))
                ctx.stroke(p, with: .color(.white.opacity(0.07)), lineWidth: 1)
                label(Format.number(v), L - 6, sy(v), .trailing)
                v += st
            }
            for m in stride(from: 0, through: Int(X), by: X > 12 ? 2 : 1) {
                label("\(m)", sx(Double(m)), H - 24, .center)
            }
            label(kind.unit, L - 6, 8, .trailing)
            label("alder i måneder", (L + W - R) / 2, H - 8, .center)

            // Bånd P3-P97 og P15-P85
            func band(_ a: WHO.Percentile, _ b: WHO.Percentile, _ opacity: Double) {
                var p = Path()
                p.addLines(curves.map { CGPoint(x: sx(Double($0.month)), y: sy($0[b])) }
                           + curves.reversed().map { CGPoint(x: sx(Double($0.month)), y: sy($0[a])) })
                p.closeSubpath()
                ctx.fill(p, with: .color(Color(.sRGB, red: 110 / 255, green: 160 / 255, blue: 1, opacity: opacity)))
            }
            band(.p3, .p97, 0.14)
            band(.p15, .p85, 0.18)
            var mid = Path()
            mid.addLines(curves.map { CGPoint(x: sx(Double($0.month)), y: sy($0[.p50])) })
            ctx.stroke(mid, with: .color(Color(hex: "#8fb0ff")), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

            // Målingerne
            let pts = points.compactMap { e in e.values[kind].map { CGPoint(x: sx(min(e.months, X)), y: sy($0)) } }
            if pts.count > 1 {
                var line = Path()
                line.addLines(pts)
                ctx.stroke(line, with: .color(Color(hex: "#ffd27a")), lineWidth: 2)
            }
            for (i, c) in pts.enumerated() {
                let r = i == pts.count - 1 ? 5.5 : 4
                let dot = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                ctx.fill(dot, with: .color(Color(hex: "#ffd27a")))
                ctx.stroke(dot, with: .color(Color(hex: "#0f1830")), lineWidth: 1.5)
            }
        }
        .aspectRatio(340 / 262, contentMode: .fit)
        .accessibilityLabel("Vækstkurve")
    }
}

/// «Ny måling» / «Ret måling» (`#gsheet`).
struct GrowthSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.muted) private var muted
    @State private var date: Date
    @State private var text: [WHO.Measure: String]
    @State private var error = ""
    @State private var armed = false
    let point: GrowthPoint?

    init(point: GrowthPoint?) {
        self.point = point
        _date = State(initialValue: point?.date ?? .now)
        _text = State(initialValue: Dictionary(uniqueKeysWithValues: WHO.Measure.allCases.map { m in
            (m, point?.values[m].map(Format.number) ?? "")
        }))
    }

    static let placeholders: [WHO.Measure: String] = [.weight: "fx 6,4", .length: "fx 62", .head: "fx 41"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(point == nil ? "Ny måling" : "Ret måling").font(.system(size: 18, weight: .medium)).foregroundStyle(Color.fg)
                HStack {
                    Text("Dato").font(.system(size: 14)).foregroundStyle(muted)
                    Spacer()
                    DatePicker("Dato", selection: $date, in: ...Date.now, displayedComponents: .date).labelsHidden()
                }
                .padding(.top, 14)
                ForEach(WHO.Measure.allCases, id: \.self) { m in
                    Text("\(m.name) (\(m.unit))").font(.system(size: 14)).foregroundStyle(muted).padding(.top, 14)
                    TextField("", text: Binding(get: { text[m] ?? "" }, set: { text[m] = $0 }),
                              prompt: Text(Self.placeholders[m] ?? "").foregroundStyle(muted))
                        .keyboardType(.decimalPad)
                        .field()
                }
                if !error.isEmpty {
                    Text(error).font(.system(size: 14)).foregroundStyle(Color.errorText).padding(.top, 12)
                }
                VStack(spacing: 10) {
                    GoButton(title: "Gem måling", action: save)
                    if let point {
                        GoButton(title: armed ? "Tryk igen for at slette" : "Slet måling", kind: .delete) {
                            if !armed { return armed = true }
                            model.deleteGrowth(id: point.id)
                            dismiss()
                        }
                    }
                    GoButton(title: "Annullér", kind: .ghost) { dismiss() }
                }
                .padding(.top, 14)
            }
            .padding(20)
        }
        .presentationDetents([.large])
        .presentationBackground(Color(hex: "#131c36"))
        .presentationCornerRadius(24)
        .preferredColorScheme(.dark)
    }

    func save() {
        var values: [WHO.Measure: Double?] = [:]
        for m in WHO.Measure.allCases {
            let t = (text[m] ?? "").trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                values[m] = .some(nil)
            } else if let v = parseNumber(t) {
                values[m] = v
            } else {
                return error = "\(m.name) skal være et tal"
            }
        }
        if let e = model.saveGrowth(id: point?.id, date: date, values: values) {
            error = e
        } else {
            dismiss()
        }
    }
}

/// Tøjstørrelse ud fra sidste længdemåling (kun for far, PLAN.md afsnit 5).
struct ClothingCard: View {
    var estimate: ClothingEstimate
    var name: String
    @Environment(\.muted) private var muted

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "tshirt")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(muted)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tøjstørrelse").font(.system(size: 14)).foregroundStyle(muted)
                Text("Str. \(estimate.size)").font(.system(size: 26, weight: .semibold)).foregroundStyle(Color.fg)
                if let next = estimate.nextSize, let from = estimate.nextSizeFrom {
                    Text("Str. \(next) \(Format.untilText(from, now: .now)) (ca. \(from.formatted(.dateTime.day().month(.abbreviated))))")
                        .font(.system(size: 15)).foregroundStyle(Color.fg)
                }
                Text("Skøn: \(name.isEmpty ? "barnet" : name) er ca. \(Format.number((estimate.lengthToday * 2).rounded() / 2)) cm i dag, "
                     + "ud fra målingen \(estimate.measuredAt.formatted(.dateTime.day().month(.abbreviated)))"
                     + (estimate.percentile.map { " (ca. \($0). percentil)" } ?? "")
                     + ". Størrelser varierer mellem mærker.")
                    .font(.system(size: 13)).foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .card()
        .padding(.top, 14)
    }
}
