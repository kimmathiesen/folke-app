import FolkeCore
import SwiftUI

/// Første opstart (`#onb` i index.html): barnets navn, fødselsdato, dreng/pige og «Jeg er mor/far».
/// Fødselsdato og køn spørges kun om, hvis der ikke er et barn endnu (fx delt fra partneren).
/// Kønnet bestemmer vækstkurverne og kan ændres under Indstillinger.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted
    @State private var name = ""
    @State private var birth = Date.now
    @State private var birthChosen = false
    @State private var role: Role?
    @State private var sex: Sex?
    @State private var error = ""
    @State private var importing = false

    var body: some View {
        let needsChild = !model.snapshot.hasChild
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Velkommen til Folke").font(.system(size: 18, weight: .medium))
                Text("Et par ting, før vi går i gang.")
                    .font(.system(size: 15)).foregroundStyle(muted).padding(.top, 6)

                label("Barnets navn")
                TextField("", text: $name, prompt: Text("fx Folke").foregroundStyle(muted))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .field()

                if needsChild {
                    label("Fødselsdato")
                    DatePicker("Fødselsdato", selection: Binding(get: { birth }, set: { birth = $0; birthChosen = true }),
                               in: Calendar.current.date(byAdding: .year, value: -6, to: .now)!...Date.now,
                               displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.wheel)
                        .frame(maxWidth: .infinity, maxHeight: 150)
                        .clipped()
                        .environment(\.locale, Locale(identifier: "da_DK"))

                    label("Barnet er")
                    Segmented(options: [(Sex.boy, "Dreng"), (.girl, "Pige")], selection: $sex).padding(.top, 8)
                }

                label("Jeg er")
                Segmented(options: [(Role.mor, "Mor"), (.far, "Far")], selection: $role).padding(.top, 8)

                if !error.isEmpty {
                    Text(error).font(.system(size: 14)).foregroundStyle(Color(hex: "#ff9b8f")).padding(.top, 10)
                }
                Button(action: save) {
                    Text("Kom i gang").font(.system(size: 16)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(12)
                        .background(Color.acc, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 22)

                // Kun i egne builds: start med data fra den gamle Folke-server
                if needsChild && model.importAvailable {
                    Button("Hent data fra Folke-server") { importing = true }
                        .font(.system(size: 15)).foregroundStyle(muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                }
            }
            .foregroundStyle(Color.fg)
            .padding(20)
            .background(Color(hex: "#131c36"), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.line))
            .frame(maxWidth: 480)
            .padding(18)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center)
        .onAppear {
            name = model.snapshot.childName
            role = model.role
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let text = model.importServer(url)
            if model.snapshot.hasChild {
                name = model.snapshot.childName
                error = ""
            } else {
                error = text
            }
        }
    }

    func label(_ s: String) -> some View {
        Text(s).font(.system(size: 14)).foregroundStyle(muted).padding(.top, 14)
    }

    func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return error = "Skriv barnets navn" }
        guard let clean = Format.cleanName(name) else { return error = "Skriv barnets navn (højst 40 tegn)" }
        if !model.snapshot.hasChild && !birthChosen { return error = "Vælg fødselsdato" }
        if !model.snapshot.hasChild && sex == nil { return error = "Vælg, om barnet er en dreng eller pige" }
        guard let role else { return error = "Vælg, om du er mor eller far" }
        error = ""
        model.finishOnboarding(name: clean, birthDate: birth, sex: sex ?? .boy, role: role)
    }
}

extension View {
    /// Tekstfelt som `.sh input` i webappen.
    func field() -> some View {
        padding(.vertical, 11)
            .padding(.horizontal, 12)
            .font(.system(size: 17))
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line))
            .padding(.top, 6)
    }
}
