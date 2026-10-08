import ActivityKit
import AppIntents
import FolkeCore
import SwiftUI
import WidgetKit

/// Kørende søvn på låseskærmen og i Dynamic Island. Tælleren kører af sig selv (`Text(timerInterval:)`).
struct SleepLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepActivityAttributes.self) { ctx in
            LockScreenSleepView(name: ctx.attributes.childName, childID: ctx.attributes.childID, state: ctx.state)
                .activityBackgroundTint(Color(.sRGB, red: 15 / 255, green: 24 / 255, blue: 48 / 255, opacity: 0.92))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(ctx.attributes.childName.isEmpty ? "Sover" : "\(ctx.attributes.childName) sover",
                          systemImage: "moon.zzz.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.nightW)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: ctx.state.start...Date.distantFuture, countsDown: false)
                        .font(.system(size: 22, weight: .light))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(subtitle(ctx.state)).font(.system(size: 13)).foregroundStyle(.secondary)
                        Spacer()
                        Button(intent: StopSleepIntent(childID: ctx.attributes.childID)) { Label("Stop søvn", systemImage: "stop.fill") }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .tint(Color(.sRGB, red: 224 / 255, green: 104 / 255, blue: 90 / 255))
                    }
                }
            } compactLeading: {
                Image(systemName: "moon.zzz.fill").foregroundStyle(Color.nightW)
            } compactTrailing: {
                Text(timerInterval: ctx.state.start...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "moon.zzz.fill").foregroundStyle(Color.nightW)
            }
        }
    }
}

func subtitle(_ s: SleepActivityAttributes.ContentState) -> String {
    let started = "\(s.nap ? "Lur" : "Nat") fra kl. \(Format.time(s.start))"
    guard let w = s.expectedWake else { return started }
    return "\(started) · vågen ca. \(Format.time(w))"
}

struct LockScreenSleepView: View {
    var name: String
    var childID: String
    var state: SleepActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color.nightW)
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "Sover" : "\(name) sover").font(.system(size: 15, weight: .semibold))
                Text(timerInterval: state.start...Date.distantFuture, countsDown: false)
                    .font(.system(size: 30, weight: .light))
                    .monospacedDigit()
                Text(subtitle(state)).font(.system(size: 13)).foregroundStyle(Color.mutedW)
            }
            .foregroundStyle(Color.fgW)
            Spacer()
            Button(intent: StopSleepIntent(childID: childID)) {
                Image(systemName: "stop.fill").font(.system(size: 18))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(Color(.sRGB, red: 224 / 255, green: 104 / 255, blue: 90 / 255))
        }
        .padding(16)
    }
}
