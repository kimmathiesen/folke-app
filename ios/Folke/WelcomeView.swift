import SwiftUI

/// Vises én gang pr. enhed før opsætningen: Folke er en hjælp, ikke en regel. Teksten står også nederst i Indstillinger.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted

    static let points: [(icon: String, text: String)] = [
        ("moon.stars", "Folke giver et bud på, hvornår dit barn bliver træt, ud fra jeres egne registreringer. "
            + "Det er en hjælp og ikke en regel."),
        ("eye", "Alle børn og alle dage er forskellige. Se på dit barn: gaben, gnubben i øjnene og uro siger mere end uret."),
        ("stethoscope", "Folke er ikke medicinsk rådgivning. Er du bekymret for dit barns søvn, mad eller vækst, "
            + "så tal med sundhedsplejersken eller lægen."),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                MoonLogo()
                Text("Du kender dit barn bedst")
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Self.points, id: \.icon) { p in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: p.icon)
                                .font(.title3.weight(.light))
                                .foregroundStyle(Color.acc)
                                .frame(width: 28)
                            Text(p.text).font(.callout).foregroundStyle(Color.fg)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 22)
                Button { model.welcomeSeen = true } label: {
                    Text("Det forstår jeg").font(.callout).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(12)
                        .background(Color.acc, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 26)
            }
            .foregroundStyle(Color.fg)
            .padding(22)
            .background(Color(hex: "#131c36"), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.line))
            .frame(maxWidth: 480)
            .padding(18)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center)
    }
}
