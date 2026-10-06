import FolkeCore
import SwiftUI

extension Color {
    init(_ c: RGB, opacity: Double = 1) {
        self.init(.sRGB, red: c.r / 255, green: c.g / 255, blue: c.b / 255, opacity: opacity)
    }

    static let fgW = Color(.sRGB, red: 233 / 255, green: 237 / 255, blue: 248 / 255)
    static let mutedW = Color(.sRGB, red: 220 / 255, green: 228 / 255, blue: 1, opacity: 0.7)
    static let nightW = Color(Theme.night)
}

/// Himlen efter tid på dagen (som appens baggrund), til widgets på hjemmeskærmen.
struct WidgetSky: View {
    var date: Date

    var body: some View {
        let h = Theme.hour(of: date), sky = Theme.sky(hour: h)
        ZStack {
            LinearGradient(colors: [Color(sky.top), Color(sky.bottom)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(Theme.ringColor(hour: h), opacity: sky.glow), .clear],
                           center: .top, startRadius: 0, endRadius: 140)
        }
    }
}
