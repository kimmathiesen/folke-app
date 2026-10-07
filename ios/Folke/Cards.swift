import FolkeCore
import SwiftUI

/// Forslag øverst på forsiden (`#sug`). Intet ændres uden svar.
struct SuggestionCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted
    var suggestion: Suggestions.Suggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Forslag").font(.system(size: 14)).foregroundStyle(muted)
            Text(suggestion.text).font(.system(size: 16, weight: .medium)).foregroundStyle(Color.fg)
            ActionRow(options: [("Ja, gør det", { model.answer(.yes) }),
                                ("Ikke nu", { model.answer(.later) }),
                                ("Aldrig", { model.answer(.never) })])
                .font(.system(size: 15))
                .padding(.top, 12)
        }
        .card()
    }
}

/// «Glemte du at trykke?» (`#late` og `#wake`): faldt i søvn kl., eller vågnede kl., mens søvnen kører.
struct ForgotCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted
    @State private var time: Date?
    var sleeping: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                CardIcon(name: "bed.double")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Glemte du at trykke?").font(.system(size: 16, weight: .medium)).foregroundStyle(Color.fg)
                    Text(sleeping ? "Vågnede kl." : "Faldt i søvn kl.").font(.system(size: 14)).foregroundStyle(muted)
                }
                Spacer(minLength: 0)
                OptionalTimeField(time: $time)
            }
            if let time {
                GoButton(title: "Gem") {
                    model.forgot(time)
                    if model.error == nil { self.time = nil }
                }
                .padding(.top, 12)
            }
        }
        .card()
        .onChange(of: sleeping) { time = nil }
    }
}

/// Mad (`#feed`): amning, flaske og fast føde, plus linjen med sidste måltid.
struct FeedCard: View {
    enum Mode: Hashable { case breast, bottle, solid }

    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted
    @State private var mode: Mode?
    @State private var milk: Milk? = .breast
    @State private var ml = ""
    @State private var note = ""
    @State private var time: Date?
    @FocusState private var focused: Bool
    var now: Date

    var body: some View {
        let s = model.snapshot
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                CardIcon(name: "waterbottle")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Mad").font(.system(size: 16, weight: .medium)).foregroundStyle(Color.fg)
                    Text(s.lastFeed.map { Format.lastFeed(kind: $0.kind, amountMl: $0.amountMl, time: $0.time, now: now) }
                         ?? "Ingen måltider endnu")
                        .font(.system(size: 14)).foregroundStyle(muted)
                }
            }
            Segmented(options: [(Mode.breast, "Amning"), (.bottle, "Flaske"), (.solid, "Fast føde")]
                        .filter { ($0.0 != .breast || s.featureBreast) && ($0.0 != .solid || s.featureSolids) },
                      selection: $mode, toggles: true)
                .padding(.top, 12)
            if mode != nil {
                HStack {
                    Text("Tidspunkt (valgfrit)").font(.system(size: 14)).foregroundStyle(muted)
                    Spacer()
                    OptionalTimeField(time: $time)
                }
                .padding(.top, 12)
            }
            switch mode {
            case .breast:
                ActionRow(options: [("Venstre", { save(.left) }), ("Højre", { save(.right) }), ("Begge", { save(.both) })])
                    .padding(.top, 12)
            case .bottle:
                Segmented(options: [(Milk.breast, "Modermælk"), (.formula, "Erstatning")], selection: $milk)
                    .padding(.top, 12)
                HStack(spacing: 10) {
                    TextField("", text: $ml, prompt: Text("ml").foregroundStyle(muted))
                        .keyboardType(.decimalPad).focused($focused).inputFrame()
                    GoButton(title: "Gem flaske") {
                        guard let v = parseNumber(ml), v > 0 else { return model.error = "Skriv hvor mange ml" }
                        save(.bottle, amount: v)
                    }
                    .fixedSize()
                }
                .padding(.top, 12)
            case .solid:
                HStack(spacing: 10) {
                    TextField("", text: $note, prompt: Text(solidPrompt).foregroundStyle(muted))
                        .focused($focused).inputFrame()
                    GoButton(title: "Gem") { save(.solid) }.fixedSize()
                }
                .padding(.top, 12)
            case nil:
                EmptyView()
            }
        }
        .card()
        .onChange(of: s.featureBreast) { if !s.featureBreast && mode == .breast { mode = nil } }
        .onChange(of: s.featureSolids) { if !s.featureSolids && mode == .solid { mode = nil } }
    }

    var solidPrompt: String {
        (model.store.child()?.sex == Sex.girl.rawValue) ? "Hvad spiste hun? (valgfrit)" : "Hvad spiste han? (valgfrit)"
    }

    func save(_ kind: FeedKind, amount: Double? = nil) {
        focused = false
        if model.feed(kind, amountMl: amount, milk: milk ?? .breast, note: note, at: time) {
            mode = nil
            ml = ""
            note = ""
            time = nil
        }
    }
}

/// Udpumpning (`#pumpc`): ml, side, minutter og tidspunkt, plus dagens opsummering.
struct PumpCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted
    @State private var side: Side?
    @State private var ml = ""
    @State private var minutes = ""
    @State private var time: Date?
    @FocusState private var focused: Bool
    var now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                CardIcon(name: "drop")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Udpumpning").font(.system(size: 16, weight: .medium)).foregroundStyle(Color.fg)
                    Text(Format.pumpSummary(model.snapshot.pump, now: now)).font(.system(size: 14)).foregroundStyle(muted)
                }
                Spacer(minLength: 0)
                Button { model.page = .pump } label: {
                    Text("Historik ›").font(.system(size: 14)).foregroundStyle(Color.acc)
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
            Segmented(options: [(Side.left, "Venstre"), (.right, "Højre"), (.both, "Begge")], selection: $side, toggles: true)
                .padding(.top, 12)
            HStack(spacing: 10) {
                TextField("", text: $ml, prompt: Text("ml").foregroundStyle(muted))
                    .keyboardType(.decimalPad).focused($focused).inputFrame()
                TextField("", text: $minutes, prompt: Text("minutter (valgfrit)").foregroundStyle(muted))
                    .keyboardType(.numberPad).focused($focused).inputFrame()
            }
            .padding(.top, 12)
            HStack {
                Text("Tidspunkt (valgfrit)").font(.system(size: 14)).foregroundStyle(muted)
                Spacer()
                OptionalTimeField(time: $time)
            }
            .padding(.top, 12)
            GoButton(title: "Gem udpumpning", action: save).padding(.top, 12)
        }
        .card()
    }

    func save() {
        guard let v = parseNumber(ml), v > 0 else { return model.error = "Skriv hvor mange ml" }
        let m = minutes.trimmingCharacters(in: .whitespaces)
        guard m.isEmpty || parseNumber(m) != nil else { return model.error = "Ugyldigt antal minutter" }
        focused = false
        if model.pump(amountMl: v, side: side, minutes: parseNumber(m), at: time) {
            side = nil
            ml = ""
            minutes = ""
            time = nil
        }
    }
}

/// En funktion fra Folke Plus, der er låst: kort forklaring i stedet for funktionen (aldrig et pop-op midt i brugen).
struct LockedCard: View {
    var feature: Plus.Feature
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CardIcon(name: "lock", size: 46)
            VStack(alignment: .leading, spacing: 6) {
                Text(feature.lockedText).font(.system(size: 15)).foregroundStyle(Color.fg)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Se Folke Plus") { model.page = .settings }
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Color.acc)
            }
            Spacer(minLength: 0)
        }
        .card()
    }
}
