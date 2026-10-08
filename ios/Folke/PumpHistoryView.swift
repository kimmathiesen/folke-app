import FolkeCore
import SwiftUI

/// Udpumpning (siden på forsiden): registrér, plus `#v-pump` fra index.html (graf over 14 dage, liste over 7 dage, ret og slet).
struct PumpHistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted
    @State private var editing: Snapshot.PumpItem?

    var body: some View {
        let s = model.snapshot
        let h = s.pumpHistory
        TimelineView(.periodic(from: .now, by: 60)) { tl in
        ScrollView {
            VStack(spacing: 0) {
                PageTitle(title: "Udpumpning")
                PumpCard(now: tl.date)
                ErrorText().padding(.top, 8)
                VStack(alignment: .leading, spacing: 8) {
                    PumpChart(history: h)
                    if let today = h.days.last {
                        (Text("I dag: \(today.ml) ml").fontWeight(.medium).foregroundStyle(Color.fg)
                         + Text(" · \(today.count) \(today.count == 1 ? "gang" : "gange")"
                                + (h.avgMl.map { " · gennemsnit \($0) ml/dag (stiplet)" } ?? ""))
                            .foregroundStyle(muted))
                            .font(.system(size: 15))
                    }
                }
                .card()
                .padding(.top, 16)
                if !s.pumpItems.isEmpty {
                    list(s.pumpItems)
                }
                Text("Grafen viser de seneste 14 dage, listen de seneste 7. Gennemsnittet regnes kun af hele dage med udpumpning."
                     + (s.pumpRemindHours > 0 ? " Påmindelse efter \(Format.hours(s.pumpRemindHours)) timer."
                                              : " Påmindelser kan slås til under Indstillinger."))
                    .font(.system(size: 13)).foregroundStyle(muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16).padding(.horizontal, 4)
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .contentMargins(.horizontal, 18, for: .scrollContent)
        .contentMargins(.bottom, 20, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        }
        .sheet(item: $editing) { PumpSheet(item: $0) }
    }

    func list(_ items: [Snapshot.PumpItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, x in
                Button { editing = x } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(x.time.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).capitalizedFirst
                                 + " kl. \(Format.time(x.time))")
                                .font(.system(size: 17)).foregroundStyle(Color.fg)
                            Text(Format.pumpDescription(amountMl: x.amountMl, side: x.side, minutes: x.minutes))
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

/// Søjler pr. dag, i dag i gul og gennemsnittet stiplet (som `drawP` i index.html, viewBox 340×200).
struct PumpChart: View {
    var history: PumpHistory
    @Environment(\.muted) private var muted

    var body: some View {
        Canvas { ctx, size in
            let k = size.width / 340
            ctx.scaleBy(x: k, y: k)
            let D = history.days, n = D.count
            guard n > 0 else { return }
            let W = 340.0, H = 200.0, L = 34.0, R = 6.0, T = 26.0, B = 26.0, bw = (W - L - R) / Double(n)
            let mx = Double(max(100, D.map(\.ml).max() ?? 0))
            let st = [50.0, 100, 200, 250, 500, 1000].first { mx / $0 <= 5 } ?? 1000
            let top = (mx / st).rounded(.up) * st
            let sy = { (v: Double) in H - B - (H - T - B) * v / top }
            func label(_ s: String, _ x: Double, _ y: Double, _ anchor: UnitPoint) {
                ctx.draw(Text(s).font(.system(size: 11)).foregroundStyle(muted), at: CGPoint(x: x, y: y), anchor: anchor)
            }
            var v = 0.0
            while v <= top {
                var p = Path()
                p.move(to: CGPoint(x: L, y: sy(v)))
                p.addLine(to: CGPoint(x: W - R, y: sy(v)))
                ctx.stroke(p, with: .color(.white.opacity(0.07)), lineWidth: 1)
                label("\(Int(v))", L - 6, sy(v), .trailing)
                v += st
            }
            for (i, d) in D.enumerated() {
                let x = L + Double(i) * bw, today = i == n - 1
                if d.ml > 0 {
                    let r = CGRect(x: x + bw * 0.18, y: sy(Double(d.ml)), width: bw * 0.64, height: sy(0) - sy(Double(d.ml)))
                    ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(Color(hex: today ? "#ffd27a" : "#8fb0ff")))
                }
                if i % 2 == (n - 1) % 2 {
                    label(today ? "i dag" : "\(Calendar.current.component(.day, from: d.date)).", x + bw / 2, H - 12, .center)
                }
            }
            if let avg = history.avgMl {
                var p = Path()
                p.move(to: CGPoint(x: L, y: sy(Double(avg))))
                p.addLine(to: CGPoint(x: W - R, y: sy(Double(avg))))
                ctx.stroke(p, with: .color(Color.fg.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            label("ml", L - 6, 6, .trailing)
        }
        .aspectRatio(340 / 200, contentMode: .fit)
        .accessibilityLabel("Udpumpning de seneste 14 dage")
    }
}

/// «Ret udpumpning» (`#psheet`).
struct PumpSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.muted) private var muted
    @State private var time: Date
    @State private var ml: String
    @State private var side: Side?
    @State private var minutes: String
    @State private var error = ""
    @State private var armed = false
    let item: Snapshot.PumpItem

    init(item: Snapshot.PumpItem) {
        self.item = item
        _time = State(initialValue: item.time)
        _ml = State(initialValue: Format.number((item.amountMl * 10).rounded() / 10))
        _side = State(initialValue: item.side)
        _minutes = State(initialValue: item.minutes > 0 ? "\(Int(item.minutes.rounded()))" : "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ret udpumpning").font(.system(size: 18, weight: .medium)).foregroundStyle(Color.fg)
                HStack {
                    Text("Tidspunkt").font(.system(size: 14)).foregroundStyle(muted)
                    Spacer()
                    DatePicker("Tidspunkt", selection: $time).labelsHidden()
                }
                .padding(.top, 14)
                Text("Mængde (ml)").font(.system(size: 14)).foregroundStyle(muted).padding(.top, 14)
                TextField("", text: $ml).keyboardType(.decimalPad).field()
                Segmented(options: [(Side.left, "Venstre"), (.right, "Højre"), (.both, "Begge")], selection: $side, toggles: true)
                    .padding(.top, 12)
                Text("Minutter (valgfrit)").font(.system(size: 14)).foregroundStyle(muted).padding(.top, 14)
                TextField("", text: $minutes).keyboardType(.numberPad).field()
                if !error.isEmpty {
                    Text(error).font(.system(size: 14)).foregroundStyle(Color.errorText).padding(.top, 12)
                }
                VStack(spacing: 10) {
                    GoButton(title: "Gem ændringer", action: save)
                    GoButton(title: armed ? "Tryk igen for at slette" : "Slet udpumpning", kind: .delete) {
                        if !armed { return armed = true }
                        model.deletePumping(id: item.id)
                        dismiss()
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
        guard let v = parseNumber(ml) else { return error = "Ugyldig mængde" }
        let m = minutes.trimmingCharacters(in: .whitespaces)
        guard m.isEmpty || parseNumber(m) != nil else { return error = "Ugyldigt antal minutter" }
        if let e = model.editPumping(id: item.id, time: time, amountMl: v, side: side, minutes: parseNumber(m)) {
            error = e
        } else {
            dismiss()
        }
    }
}
