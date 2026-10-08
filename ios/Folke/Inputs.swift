import FolkeCore
import SwiftUI

/// Ramme som `input` i webappen.
struct InputFrame: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body)
            .foregroundStyle(Color.fg)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line))
    }
}

extension View {
    func inputFrame() -> some View { modifier(InputFrame()) }
}

/// Et klokkeslæt, der kan stå tomt (som `<input type=time>`). Tomt = nu.
struct OptionalTimeField: View {
    @Binding var time: Date?
    @Environment(\.muted) private var muted

    var body: some View {
        if let t = time {
            HStack(spacing: 6) {
                DatePicker("Tidspunkt", selection: Binding(get: { t }, set: { time = $0 }),
                           displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Button { time = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ryd tidspunkt")
            }
        } else {
            Button { time = .now } label: {
                Text("--.--").monospacedDigit().foregroundStyle(muted)
                    .lineLimit(1)
                    .frame(minWidth: 64)
                    .inputFrame()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Vælg tidspunkt")
        }
    }
}

/// Tal med komma eller punktum ("6,4"). nil, hvis feltet er tomt eller ugyldigt.
func parseNumber(_ s: String) -> Double? {
    Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
}

/// Knapper som `.seg`, hvor hver knap udfører en handling (fx Venstre/Højre/Begge ved amning).
struct ActionRow: View {
    var options: [(String, () -> Void)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options.indices, id: \.self) { i in
                Button(action: options[i].1) {
                    Text(options[i].0).segLabel(on: false)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension Text {
    func segLabel(on: Bool) -> some View {
        font(.callout)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .foregroundStyle(on ? Color(hex: "#0b1224") : .fg)
            .background(on ? Color.fg : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(on ? Color.fg : .line))
    }
}

/// Fuld bredde-knap som `.go` (blå), `.go.del` (rød) og `.go.ghost`.
struct GoButton: View {
    enum Kind { case primary, delete, ghost }
    var title: String
    var kind: Kind = .primary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .foregroundStyle(kind == .ghost ? Color.white.opacity(0.62) : .white)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(kind == .primary ? Color.acc : kind == .delete ? Color(hex: "#c4524a") : .clear,
                            in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(kind == .ghost ? Color.line : .clear))
        }
        .buttonStyle(.plain)
    }
}

/// Ikon i kortene (tynd streg i den dæmpede farve).
struct CardIcon: View {
    var name: String
    var size: CGFloat = 34
    @Environment(\.muted) private var muted
    /// Følger tekststørrelsen (Dynamic Type)
    @ScaledMetric private var scale: CGFloat = 1

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size * 0.72 * scale, weight: .light))
            .foregroundStyle(muted)
            .frame(width: size * scale, height: size * scale)
            .accessibilityHidden(true) // kun pynt
    }
}
