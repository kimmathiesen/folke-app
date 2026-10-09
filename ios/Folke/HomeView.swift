import FolkeCore
import SwiftUI

/// Forsiden: sider, man stryger mellem som på iPhones hjemmeskærm (Søvn, Mad, Udpumpning, Vækst). Søvn er standard.
/// Indstillinger og månen (tavlen) ligger fast i toppen, sidevælgeren i bunden.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    // Vandret ScrollView med sidevis rulning (ikke TabView(.page), der gav en uendelig layoutløkke med siderne her)
    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            GeometryReader { g in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(model.tabs, id: \.self) { t in
                            page(t).frame(width: g.size.width, height: g.size.height)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: Binding(get: { model.tab }, set: { if let t = $0 { model.tab = t } }))
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
            PageIndicator()
        }
    }

    @ViewBuilder func page(_ t: AppModel.Tab) -> some View {
        switch t {
        case .sleep: SleepPage()
        case .food: FoodPage()
        case .pump: PumpHistoryView()
        case .growth: GrowthView()
        }
    }
}

/// Fast top: «Indstillinger» til venstre og månen (tavlen) i midten (`#setbtn` og logoet i webappen).
struct TopBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button { model.openBoard() } label: { MoonLogo(blink: model.boardHasNews) }
            .buttonStyle(.plain)
            .accessibilityLabel("Tavlen")
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
                Button { model.page = .settings } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3").font(.subheadline)
                        Text("Indstillinger").font(.subheadline)
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
                // Kun ved flere børn
                if model.snapshot.children.count > 1 { ChildPicker().padding(.top, 8) }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .dynamicTypeSize(...DynamicTypeSize.xLarge) // bjælke: vokser med, men ikke ind over månen
    }
}

/// Sidevælgeren i bunden: navnene på siderne, den aktuelle fremhævet. Tryk eller stryg.
struct PageIndicator: View {
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted

    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.tabs, id: \.self) { t in
                let on = t == model.tab
                Button { withAnimation(.easeInOut(duration: 0.25)) { model.tab = t } } label: {
                    Text(t.title)
                        .font(.footnote.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.fg : muted)
                        .padding(.vertical, 7).padding(.horizontal, 12)
                        .background(on ? Color.white.opacity(0.12) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.line))
        .padding(.top, 6)
        .padding(.bottom, 4)
        .lineLimit(1)
        .dynamicTypeSize(...DynamicTypeSize.xLarge) // som faneblade: vokser med op til en grænse
    }
}

/// Titel øverst på en side (Mad, Udpumpning, Vækst)
struct PageTitle: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.title.weight(.semibold))
            .foregroundStyle(Color.fg)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
            .padding(.bottom, 14)
    }
}

/// Fejltekst fra seneste handling (vises på den side, man står på)
struct ErrorText: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let e = model.error {
            Text(e).font(.subheadline).foregroundStyle(Color.errorText)
        }
    }
}

/// Søvn: hilsen, ringen, start/stop, glemte tryk, næste lur og dagens søvn.
struct SleepPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            GeometryReader { g in
                ScrollView {
                    // iPad på langs: ring til venstre, kort til højre (fra 900 pt)
                    if g.size.width >= 900 {
                        VStack(spacing: 0) {
                            greeting
                            suggestion.frame(maxWidth: 600)
                            HStack(alignment: .top, spacing: 40) {
                                dialColumn(now: tl.date, maxDial: 420)
                                cards(now: tl.date).padding(.top, 6)
                            }
                        }
                        .frame(maxWidth: 1040)
                    } else {
                        VStack(spacing: 0) {
                            greeting
                            suggestion
                            dialColumn(now: tl.date, maxDial: g.size.width >= 600 ? 420 : 360)
                            cards(now: tl.date)
                        }
                        .frame(maxWidth: g.size.width >= 600 ? 600 : 440)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentMargins(.horizontal, 18, for: .scrollContent)
                .contentMargins(.bottom, 20, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    var greeting: some View {
        VStack(spacing: 0) {
            Text(Format.greeting(name: model.snapshot.childName, role: model.role))
                .font(.title.weight(.semibold))
                .foregroundStyle(Color.fg)
                .padding(.top, 2)
                .padding(.bottom, 4)
            Text("Små drømme, store øjeblikke ♡")
                .font(.subheadline)
                .foregroundStyle(muted)
        }
    }

    func dialColumn(now: Date, maxDial: Double) -> some View {
        VStack(spacing: 0) {
            DialView(snapshot: model.snapshot, now: now)
                .frame(maxWidth: maxDial)
                .padding(.top, 6)
            legend
            sleepButton
            if let r = model.snapshot.running {
                Segmented(options: [(true, "Lur"), (false, "Nat")], selection: Binding(
                    get: { model.isNap }, set: { model.napSelection = $0 }), pill: true)
                    .padding(.top, 16)
                if !model.isNap {
                    // Opvågning om natten
                    let awake = r.wakes.contains { $0.end == nil }
                    Button { model.toggleWake() } label: {
                        Label(awake ? "Sover igen" : "Vågnede", systemImage: awake ? "moon.zzz" : "eye")
                            .font(.subheadline).foregroundStyle(Color.fg)
                            .padding(.vertical, 9).padding(.horizontal, 20)
                            .background(Color.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.line))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                }
            }
            if !model.snapshot.twins.isEmpty { TwinRow(now: now).padding(.top, 14) }
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
        .font(.footnote)
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
                Image(systemName: sleeping ? "stop.fill" : "play.fill").font(.body)
                Text(sleeping ? "Stop søvn" : "Start søvn").font(.title3.weight(.medium))
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
            PlanCard(snapshot: s, now: now)
            ErrorText()
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
        // Uden Folke Plus er der ingen dagsplan, kun den enkle forudsigelse
        if plan == nil, let p = prediction { return Next(kind: p.kind, time: p.time, now: false) }
        guard let p = plan, p.wake == nil, let f = p.items.first else { return nil }
        return Next(kind: f.kind, time: f.start,
                    now: p.missedAt != nil && f.kind == .nap && f.start <= now.addingTimeInterval(60))
    }
}

/// Tvillinger: tvillingens status (tryk for at skifte) og «Start begge» / «Stop begge», når det giver mening.
struct TwinRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted
    var now: Date

    var body: some View {
        let s = model.snapshot
        let mine = s.running != nil
        let theirs = s.twins.map { $0.since != nil }
        VStack(spacing: 10) {
            ForEach(s.twins) { t in
                Button { model.selectChild(t.id) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: t.since == nil ? "sun.max" : "moon.zzz.fill")
                        Text(t.since.map { "\(t.name) sover · siden \(Format.time($0))" } ?? "\(t.name) er vågen")
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(muted)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Skift til \(t.name)")
            }
            if !mine && !theirs.contains(true) {
                pill("Start begge", "play.fill") { model.startBoth() }
            } else if mine && !theirs.contains(false) {
                pill("Stop begge", "stop.fill") { model.stopBoth() }
            }
        }
    }

    func pill(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.fg)
                .padding(.vertical, 9).padding(.horizontal, 18)
                .background(Color.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.line))
        }
        .buttonStyle(.plain)
    }
}

/// Gratisudgaven: én diskret linje om dagsplanen i Folke Plus (aldrig et pop-op)
struct PlusHint: View {
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted

    var body: some View {
        Button { model.page = .settings } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "sparkles")
                Text("Resten af dagen og en plan, der tilpasser sig, er med i Folke Plus ›")
                    .multilineTextAlignment(.leading)
            }
            .font(.footnote)
            .foregroundStyle(muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
        }
        .buttonStyle(.plain)
    }
}

/// Kortet «Næste lur» med resten af dagen (`#pred` og `planUI` i index.html).
struct PlanCard: View {
    var snapshot: Snapshot
    var now: Date
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted

    var window: Int { model.planWindow }

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
            return ("Sengetid", span(n.time), "Luren kl. \(Format.time(missed)) blev ikke til noget"
                    + (moved > 0 ? ", så sengetid er rykket \(moved) min frem." : "."))
        }
        if let p = snapshot.prediction {
            return (p.kind == .nap ? "Næste lur" : "Sengetid", span(n?.time ?? p.time), Format.why(p) + hit)
        }
        return nil
    }

    /// Vinduet, enheden har valgt under Indstillinger (træfsikkerheden står i «typisk ±X min»)
    func span(_ t: Date) -> String {
        Format.span(t, window: window, interval: snapshot.accuracy?.interval ?? (-20, 20))
    }

    var hit: String {
        guard let a = snapshot.accuracy, a.n >= 8 else { return "" }
        let m = Int(a.medianAbs.rounded())
        return m < 5 ? " · typisk inden for 5 min" : " · typisk ±\(m) min"
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
                        Text(k).font(.subheadline).foregroundStyle(muted)
                        Text(big).font(.title.weight(.semibold)).foregroundStyle(Color.fg)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(sub).font(.subheadline).foregroundStyle(muted)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(k): \(big.replacingOccurrences(of: "–", with: " til ")). \(sub)")
                if let P = snapshot.plan {
                    let rest = P.items.enumerated().filter { P.wake != nil || $0.offset > 0 }.map(\.element)
                    if !rest.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Resten af dagen").font(.footnote).foregroundStyle(muted)
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
                                .font(.subheadline)
                            }
                        }
                        .padding(.top, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
                        .padding(.top, 12)
                    }
                }
                if !snapshot.plus.unlocked { PlusHint().padding(.top, 12) }
            }
            .card()
        }
    }
}
