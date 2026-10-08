import FolkeCore
import SwiftUI

/// Første opstart (`#onb` i index.html): barnets navn, fødselsdato, dreng/pige og «Jeg er mor/far».
/// Fødselsdato og køn spørges kun om, hvis der ikke er et barn endnu (fx delt fra partneren).
/// Kønnet bestemmer vækstkurverne og kan ændres under Indstillinger.
/// Flere børn kan oprettes med det samme («+ Tilføj endnu et barn»), fx tvillinger eller en storesøster.
struct OnboardingView: View {
    /// Et ekstra barn i opsætningen. Tvilling = samme fødselsdato som det første barn.
    struct Extra: Identifiable {
        let id = UUID()
        var name = ""
        var birth = Date.now
        var birthChosen = false
        var twin = false
        var sex: Sex?
    }

    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted
    @State private var name = ""
    @State private var birth = Date.now
    @State private var birthChosen = false
    @State private var role: Role?
    @State private var sex: Sex?
    @State private var error = ""
    @State private var importing = false
    @State private var extras: [Extra] = []

    var body: some View {
        let needsChild = !model.snapshot.hasChild
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Velkommen til Folke").font(.headline)
                Text("Et par ting, før vi går i gang.")
                    .font(.subheadline).foregroundStyle(muted).padding(.top, 6)

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

                    ForEach($extras) { $e in extraBlock($e) }
                    Button { withAnimation { extras.append(Extra()) } } label: {
                        Label("Tilføj endnu et barn", systemImage: "plus")
                            .font(.subheadline).foregroundStyle(Color.acc)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                }

                label("Jeg er")
                Segmented(options: [(Role.mor, "Mor"), (.far, "Far")], selection: $role).padding(.top, 8)

                if !error.isEmpty {
                    Text(error).font(.subheadline).foregroundStyle(Color(hex: "#ff9b8f")).padding(.top, 10)
                }
                Button(action: save) {
                    Text("Kom i gang").font(.callout).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(12)
                        .background(Color.acc, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 22)

                // Kun i egne builds: start med data fra den gamle Folke-server
                if needsChild && model.importAvailable {
                    Button("Hent data fra Folke-server") { importing = true }
                        .font(.subheadline).foregroundStyle(muted)
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

    /// Et ekstra barn: navn, tvilling eller egen fødselsdato, dreng/pige og «Fjern».
    func extraBlock(_ e: Binding<Extra>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Barn \((extras.firstIndex { $0.id == e.wrappedValue.id } ?? 0) + 2)")
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Fjern") { withAnimation { extras.removeAll { $0.id == e.wrappedValue.id } } }
                    .font(.subheadline).foregroundStyle(muted)
            }
            label("Navn")
            TextField("", text: e.name, prompt: Text("Barnets navn").foregroundStyle(muted))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .field()
            Toggle("Tvilling (samme fødselsdato)", isOn: e.twin)
                .tint(Color.acc)
                .font(.subheadline)
                .padding(.top, 12)
            if !e.wrappedValue.twin {
                label("Fødselsdato")
                DatePicker("Fødselsdato", selection: Binding(get: { e.wrappedValue.birth },
                                                             set: { e.wrappedValue.birth = $0; e.wrappedValue.birthChosen = true }),
                           in: Calendar.current.date(byAdding: .year, value: -6, to: .now)!...Date.now,
                           displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.wheel)
                    .frame(maxWidth: .infinity, maxHeight: 150)
                    .clipped()
                    .environment(\.locale, Locale(identifier: "da_DK"))
            }
            label("Barnet er")
            Segmented(options: [(Sex.boy, "Dreng"), (.girl, "Pige")], selection: e.sex).padding(.top, 8)
        }
        .padding(.top, 18)
        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1).padding(.top, 6) }
    }

    func label(_ s: String) -> some View {
        Text(s).font(.subheadline).foregroundStyle(muted).padding(.top, 14)
    }

    func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return error = "Skriv barnets navn" }
        guard let clean = Format.cleanName(name) else { return error = "Skriv barnets navn (højst 40 tegn)" }
        if !model.snapshot.hasChild && !birthChosen { return error = "Vælg fødselsdato" }
        if !model.snapshot.hasChild && sex == nil { return error = "Vælg, om barnet er en dreng eller pige" }
        var more: [(name: String, birthDate: Date, sex: Sex)] = []
        if !model.snapshot.hasChild {
            for (i, e) in extras.enumerated() {
                let n = "barn \(i + 2)"
                guard let c = Format.cleanName(e.name) else { return error = "Skriv navnet på \(n) (højst 40 tegn)" }
                if !e.twin && !e.birthChosen { return error = "Vælg fødselsdato for \(c)" }
                guard let s = e.sex else { return error = "Vælg, om \(c) er en dreng eller pige" }
                more.append((c, e.twin ? birth : e.birth, s))
            }
        }
        guard let role else { return error = "Vælg, om du er mor eller far" }
        error = ""
        model.finishOnboarding(name: clean, birthDate: birth, sex: sex ?? .boy, role: role, more: more)
    }
}

extension View {
    /// Tekstfelt som `.sh input` i webappen.
    func field() -> some View {
        padding(.vertical, 11)
            .padding(.horizontal, 12)
            .font(.body)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line))
            .padding(.top, 6)
    }
}
