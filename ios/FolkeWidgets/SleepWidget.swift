import AppIntents
import FolkeCore
import SwiftUI
import WidgetKit

/// Hvad widgetten viser: søvn i gang eller vågen, næste punkt i dagsplanen og resten af dagen.
struct SleepEntry: TimelineEntry {
    var date: Date
    var hasChild = false
    var name = ""
    var sleepingSince: Date?
    var awakeSince: Date?
    var expectedWake: Date?
    var next: PlanItem?
    var nextNow = false
    var rest: [PlanItem] = []
    var catnap = false
    /// Uden Folke Plus viser widgetten kun en henvisning til appen
    var locked = false

    static let placeholder: SleepEntry = {
        let now = Date.now
        return SleepEntry(date: now, hasChild: true, name: "Folke", awakeSince: now.addingTimeInterval(-80 * 60),
                          next: PlanItem(kind: .nap, start: now.addingTimeInterval(40 * 60), end: now.addingTimeInterval(110 * 60)))
    }()
}

struct SleepProvider: TimelineProvider {
    func placeholder(in context: Context) -> SleepEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (SleepEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task { @MainActor in completion(Self.entry(now: .now)) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<SleepEntry>) -> Void) {
        Task { @MainActor in
            let now = Date.now
            let e = Self.entry(now: now)
            // Næste gang noget skifter: planens næste tidspunkt (og 16 min efter, hvor en misset lur bliver «nu»), dog højst 15 min
            var next = now.addingTimeInterval(15 * 60)
            if let t = e.next?.start, t > now { next = min(next, t.addingTimeInterval(16 * 60)) }
            completion(Timeline(entries: [e], policy: .after(next)))
        }
    }

    @MainActor static func entry(now: Date) -> SleepEntry {
        let store = FolkeShared.store
        store.currentChildID = FolkeShared.childID // valgt i appen; widgetten lever længe
        store.context.refreshAllObjects()
        guard let child = store.child() else { return SleepEntry(date: now) }
        guard FolkeShared.plus(now: now).unlocked else { return SleepEntry(date: now, hasChild: true, locked: true) }
        var e = SleepEntry(date: now, hasChild: true, name: child.name ?? "")
        e.sleepingSince = store.runningSleep()?.start
        e.awakeSince = store.awakeSince(now: now)
        if let p = store.dayPlan(now: now) {
            e.expectedWake = p.wake
            e.catnap = p.catnap
            if p.wake == nil, let f = p.items.first {
                e.next = f
                e.nextNow = p.missedAt != nil && f.kind == .nap && f.start <= now.addingTimeInterval(60)
                e.rest = Array(p.items.dropFirst())
            } else {
                e.rest = p.items
            }
        } else if e.sleepingSince == nil, let pr = store.prediction(now: now) {
            e.next = PlanItem(kind: pr.kind, start: pr.time)
        }
        return e
    }
}

struct SleepWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FolkeSleep", provider: SleepProvider()) { entry in
            SleepWidgetView(entry: entry)
        }
        .configurationDisplayName("Folke")
        .description("Søvn i gang eller vågen, næste lur og sengetid. Start og stop søvn direkte fra widgetten.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct SleepWidgetView: View {
    var entry: SleepEntry
    @Environment(\.widgetFamily) private var family

    var sleeping: Bool { entry.sleepingSince != nil }

    /// «Næste lur ca. 13.40», «Sengetid ca. 21.07», «Næste lur: nu» eller «Vågen ca. 12.07»
    var nextText: String {
        if let w = entry.expectedWake { return "Vågen ca. \(Format.time(w))" }
        guard let n = entry.next else { return "" }
        if entry.nextNow { return "Næste lur: nu" }
        return "\(n.kind == .nap ? "Næste lur" : "Sengetid") ca. \(Format.time(n.start))"
    }

    var since: Date? { entry.sleepingSince ?? entry.awakeSince }

    var body: some View {
        Group {
            if !entry.hasChild {
                Text("Åbn Folke for at komme i gang").font(.footnote).foregroundStyle(Color.mutedW)
            } else if entry.locked {
                locked
            } else {
                switch family {
                case .accessoryInline: inline
                case .accessoryCircular: circular
                case .accessoryRectangular: rectangular
                case .systemMedium: medium
                default: small
                }
            }
        }
        .containerBackground(for: .widget) { WidgetSky(date: entry.date) }
    }

    @ViewBuilder var locked: some View {
        switch family {
        case .accessoryInline: Text("\(Image(systemName: "lock")) Folke Plus")
        case .accessoryCircular: ZStack { AccessoryWidgetBackground(); Image(systemName: "lock") }
        default:
            VStack(alignment: .leading, spacing: 4) {
                Label("Folke Plus", systemImage: "lock").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.fgW)
                Text("Widgets er med i Folke Plus. Åbn Folke for at se mere.")
                    .font(.system(size: 12)).foregroundStyle(Color.mutedW)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func counter(_ size: CGFloat) -> some View {
        Group {
            if let since {
                Text(timerInterval: since...Date.distantFuture, countsDown: false)
            } else {
                Text("--")
            }
        }
        .font(.system(size: size, weight: .light))
        .monospacedDigit()
    }

    var startStop: some View {
        Group {
            if sleeping {
                Button(intent: StopSleepIntent()) { Label("Stop", systemImage: "stop.fill") }
                    .tint(Color(.sRGB, red: 224 / 255, green: 104 / 255, blue: 90 / 255))
            } else {
                Button(intent: StartSleepIntent()) { Label("Start søvn", systemImage: "play.fill") }
                    .tint(Color(.sRGB, red: 79 / 255, green: 134 / 255, blue: 240 / 255))
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
    }

    var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: sleeping ? "moon.zzz.fill" : "sun.max.fill")
                    .foregroundStyle(sleeping ? Color.nightW : Color(Theme.ringColor(hour: 12)))
                Text(sleeping ? "Sover" : "Vågen").foregroundStyle(Color.mutedW)
            }
            .font(.system(size: 13))
            counter(26).foregroundStyle(Color.fgW).minimumScaleFactor(0.7).lineLimit(1)
            Text(nextText).font(.system(size: 12)).foregroundStyle(Color.mutedW).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            startStop
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            small
            VStack(alignment: .leading, spacing: 4) {
                Text("Resten af dagen").font(.system(size: 12)).foregroundStyle(Color.mutedW)
                ForEach(Array(entry.rest.prefix(4).enumerated()), id: \.offset) { _, x in
                    HStack {
                        Text(x.kind == .bedtime ? "Sengetid"
                             : (x.catnap || (entry.catnap && Calendar.current.component(.hour, from: x.start) >= 17)) ? "Aftenlur" : "Lur")
                        Spacer()
                        Text(Format.time(x.start)).monospacedDigit().foregroundStyle(Color.mutedW)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color.fgW)
                }
                Spacer(minLength: 0)
            }
        }
    }

    var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(sleeping ? "\(entry.name) sover" : nextText, systemImage: sleeping ? "moon.zzz.fill" : "moon")
                .font(.system(size: 14, weight: .semibold))
            counter(20)
            if sleeping, !nextText.isEmpty {
                Text(nextText).font(.system(size: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: sleeping ? "moon.zzz.fill" : "moon").font(.system(size: 14))
                if sleeping, let since = entry.sleepingSince {
                    Text(since, style: .timer).font(.system(size: 11)).monospacedDigit().multilineTextAlignment(.center)
                } else if let n = entry.next {
                    Text(entry.nextNow ? "nu" : Format.time(n.start)).font(.system(size: 12, weight: .semibold))
                }
            }
        }
    }

    var inline: some View {
        if let s = entry.sleepingSince {
            Text("\(Image(systemName: "moon.zzz.fill")) Sover siden \(Format.time(s))")
        } else {
            Text("\(Image(systemName: "moon")) \(nextText)")
        }
    }
}
