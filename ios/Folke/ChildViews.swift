import FolkeCore
import SwiftUI

extension Format {
    /// «4 mdr.», «1 år 2 mdr.», «3 år»
    static func age(birthDate: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: calendar.startOfDay(for: birthDate),
                                        to: calendar.startOfDay(for: now))
        let y = c.year ?? 0, m = c.month ?? 0
        if y == 0 { return "\(m) mdr." }
        return m == 0 ? "\(y) år" : "\(y) år \(m) mdr."
    }
}

/// Vælg barn i toppen (kun ved flere børn): navnet med en pil, og en menu med børnene og «Tilføj barn».
struct ChildPicker: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false

    var body: some View {
        let s = model.snapshot
        Menu {
            ForEach(s.children) { c in
                Button { model.selectChild(c.id) } label: {
                    if c.id == s.childID {
                        Label("\(c.name) · \(Format.age(birthDate: c.birthDate))", systemImage: "checkmark")
                    } else {
                        Text("\(c.name) · \(Format.age(birthDate: c.birthDate))")
                    }
                }
            }
            Divider()
            Button("Tilføj barn", systemImage: "plus") { adding = true }
        } label: {
            HStack(spacing: 6) {
                Text(s.childName).font(.subheadline.weight(.medium)).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
            .foregroundStyle(Color.fg)
            .padding(.vertical, 8).padding(.horizontal, 14)
            .background(Color.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.line))
        }
        .accessibilityLabel("Vælg barn, valgt: \(s.childName)")
        .sheet(isPresented: $adding) { AddChildSheet() }
    }
}

/// «Børn» (underside i Indstillinger): alle børn med alder, vælg, tilføj og slet.
struct ChildrenSettings: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false
    @State private var confirmDelete = false

    var body: some View {
        let s = model.snapshot
        Form {
            Section {
                ForEach(s.children) { c in
                    Button { model.selectChild(c.id) } label: {
                        HStack {
                            LabeledContent(c.name, value: Format.age(birthDate: c.birthDate))
                            if c.id == s.childID { Image(systemName: "checkmark").foregroundStyle(Color.acc) }
                        }
                    }
                    .foregroundStyle(Color.fg)
                    .accessibilityAddTraits(c.id == s.childID ? .isSelected : [])
                }
            } footer: {
                Text("Søvn, mad, vækst og forslag gælder det valgte barn. Udpumpning og tavlen er fælles for familien.")
            }
            .listRowBackground(Color.card)
            Section {
                Button("Tilføj barn", systemImage: "plus") { adding = true }
                if s.children.count > 1 {
                    Button("Slet \(s.childName)", systemImage: "trash", role: .destructive) { confirmDelete = true }
                }
            }
            .listRowBackground(Color.card)
        }
        .scrollContentBackground(.hidden)
        .background(SkyBackground(hour: Theme.hour(of: .now)))
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("Børn")
        .sheet(isPresented: $adding) { AddChildSheet() }
        .confirmationDialog("Slet \(s.childName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Slet \(s.childName) og alle data", role: .destructive) { model.deleteCurrentChild() }
        } message: {
            Text("Al søvn, mad og vækst for \(s.childName) slettes. Det kan ikke fortrydes. Udpumpning og tavlen bliver.")
        }
    }
}

/// Nyt barn: navn, fødselsdato og dreng/pige (som første opstart).
struct AddChildSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.muted) private var muted
    @State private var name = ""
    @State private var birth = Date.now
    @State private var sex: Sex?
    @State private var error = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Tilføj barn").font(.headline)
                Text("Navn").font(.subheadline).foregroundStyle(muted).padding(.top, 14)
                TextField("", text: $name, prompt: Text("Barnets navn").foregroundStyle(muted))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .field()
                Text("Fødselsdato").font(.subheadline).foregroundStyle(muted).padding(.top, 14)
                DatePicker("Fødselsdato", selection: $birth,
                           in: Calendar.current.date(byAdding: .year, value: -6, to: .now)!...Date.now,
                           displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.wheel)
                    .frame(maxWidth: .infinity, maxHeight: 150)
                    .clipped()
                    .environment(\.locale, Locale(identifier: "da_DK"))
                Text("Barnet er").font(.subheadline).foregroundStyle(muted).padding(.top, 14)
                Segmented(options: [(Sex.boy, "Dreng"), (.girl, "Pige")], selection: $sex).padding(.top, 8)
                if !error.isEmpty {
                    Text(error).font(.subheadline).foregroundStyle(Color.errorText).padding(.top, 10)
                }
                GoButton(title: "Gem") { save() }.padding(.top, 18)
                Button("Annullér") { dismiss() }
                    .font(.subheadline).foregroundStyle(muted)
                    .frame(maxWidth: .infinity).padding(.top, 12)
            }
            .foregroundStyle(Color.fg)
            .padding(20)
        }
        .background(Color(hex: "#131c36"))
        .presentationDetents([.large])
    }

    func save() {
        guard let sex else { return error = "Vælg, om barnet er en dreng eller pige" }
        if let e = model.addChild(name: name, birthDate: birth, sex: sex) { return error = e }
        dismiss()
    }
}
