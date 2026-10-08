import FolkeCore
import SwiftUI

@main
struct FolkeApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.id)) {
            await BackgroundRefresh.run()
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tl in
            let hour = Theme.hour(of: tl.date)
            ZStack {
                SkyBackground(hour: hour)
                if model.needsOnboarding {
                    OnboardingView()
                } else if model.page == .settings {
                    SettingsView()
                } else if model.page == .board {
                    BoardView()
                } else {
                    HomeView()
                }
            }
            .environment(\.muted, Color(.sRGB, red: 220 / 255, green: 228 / 255, blue: 1,
                                        opacity: Theme.sky(hour: hour).muted))
            .onChange(of: Calendar.current.component(.minute, from: tl.date)) { model.refresh() }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refresh() }
            if phase == .background { BackgroundRefresh.schedule() }
        }
    }
}
