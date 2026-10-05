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
                            HStack(alignment: .top, spacing: 40) {
                                dialColumn(now: tl.date, maxDial: 420)
                                cards.padding(.top, 6)
                            }
                        }
                        .frame(maxWidth: 1040)
                    } else {
                        VStack(spacing: 0) {
                            header
                            dialColumn(now: tl.date, maxDial: g.size.width >= 600 ? 420 : 360)
                            cards
                        }
                        .frame(maxWidth: g.size.width >= 600 ? 600 : 440)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentMargins(.horizontal, 18, for: .scrollContent)
                .contentMargins(.bottom, 28, for: .scrollContent)
                .scrollIndicators(.hidden)
            }
        }
    }

    var header: some View {
        VStack(spacing: 0) {
            MoonLogo()
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

    @ViewBuilder var cards: some View {
        VStack(spacing: 16) {
            if let p = model.snapshot.prediction {
                PredictionCard(prediction: p)
            }
            if let e = model.error {
                Text(e).font(.system(size: 14)).foregroundStyle(Color.errorText)
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
            Image(systemName: "face.smiling")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(muted)
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("Næste \(prediction.kind.rawValue)").font(.system(size: 14)).foregroundStyle(muted)
                Text("ca. kl. \(Format.clock(prediction.time))")
                    .font(.system(size: 26, weight: .semibold)).foregroundStyle(Color.fg)
                Text("Vindue \(prediction.windowMin) min · \(prediction.source.text)")
                    .font(.system(size: 14)).foregroundStyle(muted)
            }
            Spacer(minLength: 0)
        }
        .card()
    }
}
