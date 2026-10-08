import FolkeCore
import simd
import SwiftUI

/// Tavlen (`#v-board` i index.html): fælles kridttavle i fast format 3:4. Tryk på månen for at åbne den.
struct BoardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted
    @State private var color = Board.colors[0]
    @State private var current: [SIMD2<Float>] = []
    @State private var error = ""
    @State private var armed = false

    var body: some View {
        let strokes = model.snapshot.strokes
        GeometryReader { g in
            // Ingen ScrollView: den holder berøringer tilbage og kan tabe begyndelsen af en streg
            VStack(spacing: 0) {
                    BackHeader(title: "Tavlen") { model.page = .home }
                    let w = min(g.size.width - 36, 460, (g.size.height - 250) * 0.75)
                    chalkboard(strokes)
                        .frame(width: w - 20, height: (w - 20) * 4 / 3)
                        .padding(10)
                        .background(LinearGradient(colors: [Color(hex: "#9a7650"), Color(hex: "#5e4630")],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.35), radius: 15, y: 10)
                    palette.padding(.top, 14)
                    HStack(spacing: 8) {
                        ActionRow(options: [("Fortryd", { model.undoStroke() }),
                                            (armed ? "Tryk igen for at viske ud" : "Visk ud", clear)])
                    }
                    .frame(maxWidth: 460)
                    .padding(.top, 8)
                    Text(info(strokes)).font(.footnote).foregroundStyle(muted).padding(.top, 10)
                    if !error.isEmpty {
                        Text(error).font(.footnote).foregroundStyle(Color(hex: "#ff9b8f")).padding(.top, 6)
                    }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
        }
    }

    func chalkboard(_ strokes: [BoardStroke]) -> some View {
        GeometryReader { g in
            Canvas { ctx, size in
                for s in strokes { draw(&ctx, size, s.points, s.color, s.width) }
                if !current.isEmpty { draw(&ctx, size, current, color, Board.strokeWidth) }
            }
            .background(RadialGradient(colors: [Color(hex: "#35554a"), Color(hex: "#1c2e28")],
                                       center: UnitPoint(x: 0.3, y: 0.2), startRadius: 0, endRadius: g.size.height))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.black.opacity(0.25), lineWidth: 2).blur(radius: 6))
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let p = SIMD2(Float(min(1, max(0, v.location.x / g.size.width))),
                              Float(min(1, max(0, v.location.y / g.size.height))))
                if let l = current.last, simd_distance(p, l) < 0.004 { return }
                current.append(p)
                if current.count >= 1990 { finish() }
            }.onEnded { _ in finish() })
            .accessibilityLabel("Tavle til at tegne på")
        }
    }

    /// Kridtstreg med blød glød: kurver gennem midtpunkterne (som `stroke` i index.html)
    func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ p: [SIMD2<Float>], _ hex: String, _ width: Double) {
        let lw = width * size.width
        let pt = { (q: SIMD2<Float>) in CGPoint(x: Double(q.x) * size.width, y: Double(q.y) * size.height) }
        var c = ctx
        c.addFilter(.shadow(color: Color(hex: hex), radius: lw * 0.5))
        if p.count == 1 {
            let o = pt(p[0])
            c.fill(Path(ellipseIn: CGRect(x: o.x - lw / 2, y: o.y - lw / 2, width: lw, height: lw)), with: .color(Color(hex: hex)))
            return
        }
        var path = Path()
        path.move(to: pt(p[0]))
        for i in 1..<(p.count - 1) {
            path.addQuadCurve(to: pt((p[i] + p[i + 1]) / 2), control: pt(p[i]))
        }
        path.addLine(to: pt(p[p.count - 1]))
        c.stroke(path, with: .color(Color(hex: hex)), style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
    }

    var palette: some View {
        HStack(spacing: 14) {
            ForEach(Board.colors, id: \.self) { c in
                Button { color = c } label: {
                    Circle().fill(Color(hex: c))
                        .frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(c == color ? .white : .white.opacity(0.25), lineWidth: 2))
                        .padding(3)
                        .overlay(Circle().strokeBorder(c == color ? .white.opacity(0.25) : .clear, lineWidth: 3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(["Hvid", "Lyserød", "Gul", "Blå"][Board.colors.firstIndex(of: c) ?? 0])
            }
        }
    }

    func finish() {
        guard !current.isEmpty else { return }
        let pts = current
        current = []
        error = model.addStroke(color: color, points: pts) ?? ""
    }

    func clear() {
        if !armed {
            armed = true
            Task {
                try? await Task.sleep(for: .seconds(3))
                armed = false
            }
            return
        }
        armed = false
        model.clearBoard()
    }

    /// «Sidst ændret af far kl. 21.14» eller en opfordring, når tavlen er tom
    func info(_ strokes: [BoardStroke]) -> String {
        guard let last = strokes.last else { return "Tavlen er tom. Tegn et lille hjerte til din partner ♡" }
        let when = Calendar.current.isDateInToday(last.createdAt)
            ? "kl. \(Format.time(last.createdAt))"
            : "\(last.createdAt.formatted(.dateTime.day().month(.abbreviated))) kl. \(Format.time(last.createdAt))"
        return "Sidst ændret \(last.createdBy.map { "af \($0.rawValue) " } ?? "")\(when)"
    }
}
