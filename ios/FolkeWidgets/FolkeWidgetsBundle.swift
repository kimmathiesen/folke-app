import SwiftUI
import WidgetKit

@main
struct FolkeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SleepWidget()
        SleepLiveActivityWidget()
    }
}
