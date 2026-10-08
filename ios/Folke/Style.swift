import FolkeCore
import SwiftUI

extension Color {
    init(_ c: RGB, opacity: Double = 1) {
        self.init(.sRGB, red: c.r / 255, green: c.g / 255, blue: c.b / 255, opacity: opacity)
    }

    init(hex: String, opacity: Double = 1) {
        self.init(RGB(hex: hex), opacity: opacity)
    }

    // Som variablerne i index.html
    static let fg = Color(hex: "#e9edf8")
    static let card = Color.white.opacity(0.045)
    static let line = Color.white.opacity(0.09)
    static let acc = Color(hex: "#5b8def")
    static let errorText = Color(hex: "#ff8b7e")
}

/// Dæmpet tekst, hvis styrke følger tiden på dagen (SKY).
struct MutedKey: EnvironmentKey {
    static let defaultValue = Color(.sRGB, red: 220 / 255, green: 228 / 255, blue: 1, opacity: 0.62)
}

extension EnvironmentValues {
    var muted: Color {
        get { self[MutedKey.self] }
        set { self[MutedKey.self] = newValue }
    }
}

/// Himlen bag det hele: lodret forløb og et skær øverst i ringens farve.
struct SkyBackground: View {
    var hour: Double

    var body: some View {
        let sky = Theme.sky(hour: hour)
        GeometryReader { g in
            ZStack {
                LinearGradient(colors: [Color(sky.top), Color(sky.bottom)], startPoint: .top, endPoint: .bottom)
                // radial-gradient(120% 55% at 50% 0, glow 0, transparent 70%)
                EllipticalGradient(colors: [Color(Theme.ringColor(hour: hour), opacity: sky.glow), .clear],
                                   center: .top, startRadiusFraction: 0, endRadiusFraction: 0.7)
                    .frame(width: g.size.width * 2.4, height: g.size.height * 1.1)
                    .position(x: g.size.width / 2, y: 0)
            }
        }
        .ignoresSafeArea()
    }
}

/// Kort som `.card` i webappen.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.line))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

/// Valgknapper som `.seg` (Lur/Nat, Mor/Far).
struct Segmented<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var selection: T?
    var pill = false
    /// Et tryk mere på den valgte knap fravælger den (som side ved udpumpning).
    var toggles = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.0) { value, label in
                let on = selection == value
                Button { selection = toggles && on ? nil : value } label: {
                    Text(label)
                        .font(pill ? .subheadline : .callout)
                        .padding(.vertical, pill ? 8 : 12)
                        .padding(.horizontal, pill ? 22 : 6)
                        .frame(maxWidth: pill ? nil : .infinity)
                        .foregroundStyle(on ? Color(hex: "#0b1224") : .fg)
                        .background(on ? Color.fg : Color.white.opacity(pill ? 0.045 : 0.05),
                                    in: RoundedRectangle(cornerRadius: pill ? 99 : 14))
                        .overlay(RoundedRectangle(cornerRadius: pill ? 99 : 14).strokeBorder(on ? Color.fg : .line))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
