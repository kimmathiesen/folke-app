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
            MoonLogo()
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
            if let p = s.prediction {
                PredictionCard(prediction: p)
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

/// «Næste lur ca. kl. 13:40», vindue og kilde.
struct PredictionCard: View {
    var prediction: Prediction
    @Environment(\.muted) private var muted

    var body: some View {
        HStack(spacing: 14) {
            CardIcon(name: "face.smiling", size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("Næste \(prediction.kind.rawValue)").font(.system(size: 14)).foregroundStyle(muted)
                Text("ca. kl. \(Format.time(prediction.time))")
                    .font(.system(size: 26, weight: .semibold)).foregroundStyle(Color.fg)
                Text(Format.why(prediction))
                    .font(.system(size: 14)).foregroundStyle(muted)
            }
            Spacer(minLength: 0)
        }
        .card()
    }
}
