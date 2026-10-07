import FolkeCore
import SwiftUI

/// Forsiden (milepæl 2: overskrift, ring, start/stop og forudsigelse).
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            GeometryReader { g in
                ScrollView {
                    // iPad på langs: ring til venstre, kort til højre (fra 900 pt)
                    if g.size.width >= 900 {
                        VStack(spacing: 0) {
                            header
                            suggestion.frame(maxWidth: 600)
                            HStack(alignment: .top, spacing: 40) {
                                dialColumn(now: tl.date, maxDial: 420)
                                cards(now: tl.date).padding(.top, 6)
                            }
                        }
                        .frame(maxWidth: 1040)
                    } else {
                        VStack(spacing: 0) {
                            header
                            suggestion
                            dialColumn(now: tl.date, maxDial: g.size.width >= 600 ? 420 : 360)
                            cards(now: tl.date)
                        }
                        .frame(maxWidth: g.size.width >= 600 ? 600 : 440)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentMargins(.horizontal, 18, for: .scrollContent)
                .contentMargins(.bottom, 28, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    var header: some View {
        VStack(spacing: 0) {
            Button { model.openBoard() } label: { MoonLogo(blink: model.boardHasNews) }
                .buttonStyle(.plain)
                .accessibilityLabel("Tavlen")
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topLeading) {
                    // Som `#setbtn` i webappen
                    Button { model.page = .settings } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 14))
                            Text("Indstillinger").font(.system(size: 14))
                        }
                        .foregroundStyle(Color.fg)
                        .padding(.vertical, 8).padding(.horizontal, 14)
                        .background(Color.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.line))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .overlay(alignment: .topTrailing) {
                    // Som `#gobtn` i webappen
                    Button { model.page = .growth } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 14))
                            Text("Vækst").font(.system(size: 14))
                        }
                        .foregroundStyle(Color.fg)
                        .padding(.vertical, 8).padding(.horizontal, 14)
                        .background(Color.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.line))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
            Text(Format.greeting(name: model.snapshot.childName, role: model.role))
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.fg)
                .padding(.top, 2)
                .padding(.bottom, 4)
            Text("Små drømme, store øjeblikke ♡")
                .font(.system(size: 15))
                .foregroundStyle(muted)
        }
        .padding(.top, 14)
    }

    func dialColumn(now: Date, maxDial: Double) -> some View {
        VStack(spacing: 0) {
            DialView(snapshot: model.snapshot, now: now)
                .frame(maxWidth: maxDial)
                .padding(.top, 6)
            legend
            sleepButton
            if model.snapshot.running != nil {
                Segmented(options: [(true, "Lur"), (false, "Nat")], selection: Binding(
                    get: { model.isNap }, set: { model.napSelection = $0 }), pill: true)
                    .padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity)
    }

    var legend: some View {
        HStack(spacing: 18) {
            dot(Color(Theme.nap), "Lur")
            dot(Color(Theme.night), "Nat")
            HStack(spacing: 6) {
                Circle().strokeBorder(Color.fg, style: StrokeStyle(lineWidth: 1.5, dash: [2, 1.5]))
                    .frame(width: 9, height: 9)
                Text("Forventet næste")
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(muted)
        .padding(.bottom, 18)
    }

    func dot(_ c: Color, _ s: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 9, height: 9)
            Text(s)
        }
    }

    var sleepButton: some View {
        let sleeping = model.snapshot.running != nil
        return Button { model.toggleSleep() } label: {
            HStack(spacing: 10) {
                Image(systemName: sleeping ? "stop.fill" : "play.fill").font(.system(size: 18))
                Text(sleeping ? "Stop søvn" : "Start søvn").font(.system(size: 20, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(minWidth: 240)
            .padding(.vertical, 18)
            .padding(.horizontal, 34)
            .background(
                LinearGradient(colors: sleeping ? [Color(hex: "#e0685a"), Color(hex: "#f08a6c")]
                                                : [Color(hex: "#4f86f0"), Color(hex: "#6a9bff")],
                               startPoint: .leading, endPoint: .trailing),
                in: Capsule())
            .shadow(color: sleeping ? Color(hex: "#e0685a", opacity: 0.3) : Color(hex: "#5b8def", opacity: 0.35),
                    radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact, trigger: sleeping)
    }

    @ViewBuilder var suggestion: some View {
        if let sg = model.snapshot.suggestion {
            SuggestionCard(suggestion: sg).padding(.top, 16)
        }
    }

    func cards(now: Date) -> some View {
        let s = model.snapshot
        return VStack(spacing: 16) {
            ForgotCard(sleeping: s.running != nil)
            if s.plus.unlocked {
                PlanCard(snapshot: s, now: now)
            } else {
                LockedCard(feature: .prediction)
            }
            FeedCard(now: now)
            if s.featurePump {
                PumpCard(now: now)
            }
            if let e = model.error {
                Text(e).font(.system(size: 14)).foregroundStyle(Color.errorText)
            }
            if !s.today.isEmpty {
                DayCard(now: now)
            }
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity)
    }
}

extension Snapshot {
    /// Næste punkt i dagsplanen (`nxt` i index.html). `now`: luren skal være nu, fordi den planlagte blev sprunget over.
    struct Next {
        var kind: Prediction.Kind
        var time: Date
        var now: Bool
    }

    func next(at now: Date) -> Next? {
        guard let p = plan, p.wake == nil, let f = p.items.first else { return nil }
        return Next(kind: f.kind, time: f.start,
                    now: p.missedAt != nil && f.kind == .nap && f.start <= now.addingTimeInterval(60))
    }
}

/// Kortet «Næste lur» med resten af dagen (`#pred` og `planUI` i index.html).
struct PlanCard: View {
    var snapshot: Snapshot
    var now: Date
    @Environment(\.muted) private var muted

    /// (overskrift, stort tidspunkt, forklaring)
    var texts: (String, String, String)? {
        let P = snapshot.plan, n = snapshot.next(at: now)
        if let wake = P?.wake {
            return ("Forventet vågen", "ca. kl. \(Format.time(wake))", "Ud fra hvor længe hans lure plejer at vare")
        }
        if let n, n.now, let missed = P?.missedAt {
            return ("Næste lur", "Nu",
                    "Luren kl. \(Format.time(missed)) blev ikke til noget. Prøv at putte nu, så er resten af dagen flyttet.")
        }
        if let n, n.kind == .bedtime, let missed = P?.missedAt {
            let moved = P?.bedShift ?? 0
            return ("Sengetid", "ca. kl. \(Format.time(n.time))", "Luren kl. \(Format.time(missed)) blev ikke til noget"
                    + (moved > 0 ? ", så sengetid er rykket \(moved) min frem." : "."))
        }
        if let p = snapshot.prediction {
            return (p.kind == .nap ? "Næste lur" : "Sengetid", "ca. kl. \(Format.time(n?.time ?? p.time))", Format.why(p))
        }
        return nil
    }

    /// Aftenlur: planlagt som aftenlur, eller en lur efter kl. 17, når han plejer at tage en
    func isCatnap(_ x: PlanItem, _ p: DayPlan) -> Bool {
        x.catnap || (p.catnap && Calendar.current.component(.hour, from: x.start) >= 17)
    }

    var body: some View {
        if let (k, big, sub) = texts {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    CardIcon(name: "face.smiling", size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(k).font(.system(size: 14)).foregroundStyle(muted)
                        Text(big).font(.system(size: 26, weight: .semibold)).foregroundStyle(Color.fg)
                        Text(sub).font(.system(size: 14)).foregroundStyle(muted)
                    }
                    Spacer(minLength: 0)
                }
                if let P = snapshot.plan {
                    let rest = P.items.enumerated().filter { P.wake != nil || $0.offset > 0 }.map(\.element)
                    if !rest.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Resten af dagen").font(.system(size: 13)).foregroundStyle(muted)
                            ForEach(Array(rest.enumerated()), id: \.offset) { _, x in
                                HStack {
                                    Text(x.kind == .bedtime ? "Sengetid" : isCatnap(x, P) ? "Aftenlur" : "Lur")
                                        .foregroundStyle(Color.fg)
                                    Spacer()
                                    Text(x.kind == .bedtime
                                         ? "ca. \(Format.time(x.start))" + (P.bedShift > 0 ? " (\(P.bedShift) min tidligere)" : "")
                                         : "ca. \(Format.time(x.start))–\(Format.time(x.end ?? x.start))")
                                        .foregroundStyle(muted)
                                }
                                .font(.system(size: 15))
                            }
                        }
                        .padding(.top, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
                        .padding(.top, 12)
                    }
                }
            }
            .card()
        }
    }
}
