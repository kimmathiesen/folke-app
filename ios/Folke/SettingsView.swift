import FolkeCore
import SwiftUI
import UIKit

/// «Indstillinger» (`#v-settings` i index.html). Fælles valg gemmes i familiens data, resten kun på enheden.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var name = ""
    @State private var message = ""
    @State private var importing = false
    @State private var importMessage = ""
    @State private var exportFile: URL?
    @FocusState private var nameFocused: Bool
    @State private var serverURL = ""
    @State private var serverMessage = ""
    @State private var connecting = false
    @State private var confirmConnect = false

    static let remindOptions: [(Double, String)] = [(2, "efter 2 t"), (2.5, "efter 2½ t"), (3, "efter 3 t"),
                                                     (3.5, "efter 3½ t"), (4, "efter 4 t"), (5, "efter 5 t"),
                                                     (6, "efter 6 t")]

    var body: some View {
        let s = model.snapshot
        NavigationStack {
            Form {
                Section { PlusCard(inList: true) }
                    .listRowBackground(Color.card)

                Section("Barnet") {
                    LabeledContent("Navn") {
                        TextField("Navn", text: $name)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($nameFocused)
                            .onSubmit(save)
                    }
                    Picker("Vækstkurver", selection: Binding(get: { s.sex }, set: { model.setSex($0) })) {
                        Text("Dreng").tag(Sex.boy)
                        Text("Pige").tag(Sex.girl)
                    }
                    NavigationLink {
                        ChildrenSettings()
                    } label: {
                        LabeledContent("Børn", value: s.children.count == 1 ? "1 barn" : "\(s.children.count) børn")
                    }
                    if !message.isEmpty {
                        Text(message).font(.footnote).foregroundStyle(Color.errorText)
                    }
                }
                .listRowBackground(Color.card)

                Section {
                    Picker("Jeg er", selection: Binding(get: { model.role ?? .mor }, set: { model.role = $0 })) {
                        Text("Mor").tag(Role.mor)
                        Text("Far").tag(Role.far)
                    }
                } footer: {
                    Text("Gælder kun denne enhed.")
                }
                .listRowBackground(Color.card)

                Section("Mad og søvn") {
                    Toggle("Amning i Mad-kortet", isOn: bind(s.featureBreast) { model.setFeature(.breast, $0) })
                    Toggle("Fast føde i Mad-kortet", isOn: bind(s.featureSolids) { model.setFeature(.solids, $0) })
                    Toggle("Forudsigelse af lure", isOn: bind(s.featurePrediction) { model.setFeature(.prediction, $0) })
                }
                .listRowBackground(Color.card)

                if s.featurePrediction {
                    Section {
                        Picker("Vindue for næste lur", selection: Binding(get: { model.planWindow }, set: { model.planWindow = $0 })) {
                            ForEach(PlanWindow.options, id: \.0) { Text($0.1).tag($0.0) }
                        }
                    } footer: {
                        Text("Hvor bredt et tidsrum kortet viser omkring næste lur og sengetid. «Automatisk» bruger, "
                             + "hvor godt forudsigelsen har ramt de seneste 14 dage. Gælder kun denne enhed.")
                    }
                    .listRowBackground(Color.card)
                }

                Section {
                    Toggle("Udpumpning", isOn: bind(s.featurePump) { model.setFeature(.pump, $0) })
                    if s.featurePump {
                        Picker("Påmind", selection: Binding(get: { s.pumpRemindHours }, set: { model.setPumpRemind($0) })) {
                            ForEach(Self.remindOptions, id: \.0) { Text($0.1).tag($0.0) }
                        }
                    }
                } footer: {
                    if s.featurePump {
                        Text("Påmindelsen sendes kun til enheder, der har slået «Påmindelse om udpumpning» til under notifikationer. Ingen påmindelser mellem 22 og 7.")
                    }
                }
                .listRowBackground(Color.card)

                notifications

                Section {
                    Toggle("Vis næste tøjstørrelse", isOn: bind(model.showNextSize) { model.showNextSize = $0 })
                } header: {
                    Text("Vækst")
                } footer: {
                    Text("Skøn ud fra sidste længdemåling på vækstsiden. Gælder kun denne enhed.")
                }
                .listRowBackground(Color.card)

                Section {
                    Button("Eksportér som CSV") { exportFile = model.exportCSV() }
                } header: {
                    Text("Dine data")
                } footer: {
                    Text("Søvn, mad, udpumpning og vækst som fire CSV-filer i én zip-fil. De kan åbnes i Numbers og Excel, fx til sundhedsplejersken.")
                }
                .listRowBackground(Color.card)

                if model.importAvailable {
                    serverSection
                }

                if model.importAvailable && model.serverSync == nil {
                    Section {
                        Button("Vælg fil") { importing = true }
                        if !importMessage.isEmpty { Text(importMessage).font(.footnote) }
                    } header: {
                        Text("Importér fra Folke-server")
                    } footer: {
                        Text("Vælg eksportfilen fra serveren (folke-….json). Det, der allerede er importeret, opdateres i stedet for at blive kopieret.")
                    }
                    .listRowBackground(Color.card)
                }

                Section("Du kender dit barn bedst") {
                    ForEach(WelcomeView.points, id: \.icon) { p in
                        Label(p.text, systemImage: p.icon).font(.footnote).foregroundStyle(muted)
                    }
                }
                .listRowBackground(Color.card)
            }
            .scrollContentBackground(.hidden)
            .background(SkyBackground(hour: Theme.hour(of: .now))) // navigationen har ellers sin egen sorte baggrund
            .toolbarBackground(.hidden, for: .navigationBar)
            .tint(Color.acc)
            .navigationTitle("Indstillinger")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Tilbage", systemImage: "chevron.left") { save(); model.page = .home }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { name = s.childName }
        .onChange(of: s.childID) { name = model.snapshot.childName } // skiftet barn: vis det nye navn
        .onChange(of: nameFocused) { if !nameFocused { save() } }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await model.notifier.refreshStatus() } } }
        .sheet(isPresented: Binding(get: { exportFile != nil }, set: { if !$0 { exportFile = nil } })) {
            if let exportFile { ShareSheet(items: [exportFile]).ignoresSafeArea() }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): importMessage = model.importServer(url)
            case .failure(let error): importMessage = error.localizedDescription
            }
        }
    }

    /// Midlertidig synkronisering med Folke-serveren (kun egne builds), indtil iCloud er slået til
    @ViewBuilder var serverSection: some View {
        Section {
            if let sync = model.serverSync {
                LabeledContent("Server", value: sync.base.absoluteString)
                if !model.syncStatus.isEmpty {
                    Text(model.syncStatus).font(.footnote).foregroundStyle(muted)
                }
                Button("Hent nu") { Task { await model.pullServer() } }
                Button("Stop synkronisering", role: .destructive) { model.disconnectServer() }
            } else {
                TextField("Adresse, fx folke.mathiesen.pro", text: $serverURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(connecting ? "Forbinder …" : "Forbind") { confirmConnect = true }
                    .disabled(serverURL.trimmingCharacters(in: .whitespaces).isEmpty || connecting)
                if !serverMessage.isEmpty {
                    Text(serverMessage).font(.footnote).foregroundStyle(Color.errorText)
                }
            }
        } header: {
            Text("Synkronisering med Folke-server")
        } footer: {
            Text("Samme adresse som webappen. Midlertidigt, indtil deling via iCloud er klar. Serveren bestemmer: alt, du registrerer, sendes til den, "
                 + "og appen henter jeres fælles data hvert 20. sekund, mens den er åben. Uden forbindelse til serveren gemmes "
                 + "intet. Widgets og Siri gemmer kun på enheden.")
        }
        .listRowBackground(Color.card)
        .confirmationDialog("Forbind til Folke-serveren?", isPresented: $confirmConnect, titleVisibility: .visible) {
            Button("Forbind og hent serverens data") {
                connecting = true
                Task {
                    serverMessage = await model.connectServer(serverURL) ?? ""
                    connecting = false
                }
            }
        } message: {
            Text("Det, der kun er registreret på denne enhed for \(model.snapshot.childName), slettes, så serverens data ikke står dobbelt.")
        }
    }

    func bind(_ value: Bool, _ set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { value }, set: set)
    }

    /// Notifikationer på denne enhed: status, slå til, send test, beskedtyper og minutter.
    @ViewBuilder var notifications: some View {
        let n = model.notifier
        Section {
            LabeledContent("Status", value: n.status == .allowed ? "Slået til" : n.status == .denied ? "Blokeret" : "Slået fra")
            switch n.status {
            case .notAsked:
                Button("Slå til") {
                    Task { message = await model.requestNotifications() ? "" : "Notifikationer blev ikke tilladt" }
                }
            case .denied:
                Button("Åbn Indstillinger") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            case .allowed:
                Button("Send test") { n.sendTest() }
                Toggle("Tid til at slappe af", isOn: bind(n.enabled.contains(.sleepSoon)) { model.setNotification(.sleepSoon, $0) })
                if n.enabled.contains(.sleepSoon) {
                    Picker("Hvornår", selection: Binding(get: { n.leadMin }, set: { model.setNotificationMinutes(lead: $0) })) {
                        ForEach(NotificationPlanner.leadOptions, id: \.self) { Text("\($0) min før").tag($0) }
                    }
                }
                Toggle("Hvis lurtiden er gået", isOn: bind(n.enabled.contains(.overdue)) { model.setNotification(.overdue, $0) })
                if n.enabled.contains(.overdue) {
                    Picker("Hvornår", selection: Binding(get: { n.overdueMin }, set: { model.setNotificationMinutes(overdue: $0) })) {
                        ForEach(NotificationPlanner.overdueOptions, id: \.self) { Text("\($0) min efter").tag($0) }
                    }
                }
                if model.snapshot.featurePump {
                    Toggle("Påmindelse om udpumpning", isOn: bind(n.enabled.contains(.pump)) { model.setNotification(.pump, $0) })
                }
            case .unknown:
                EmptyView()
            }
        } header: {
            Text("Notifikationer på denne enhed")
        } footer: {
            if n.status == .denied { Text("Tillad notifikationer for Folke under Indstillinger → Notifikationer.") }
        }
        .listRowBackground(Color.card)
    }

    func save() {
        let s = model.snapshot
        guard name != s.childName else { return }
        if model.rename(name) {
            message = ""
            name = model.snapshot.childName
        } else {
            message = model.error ?? ""
            model.error = nil
        }
    }
}

/// «‹ Tilbage» med titel i midten (`.gh` i webappen).
struct BackHeader: View {
    var title: String
    var back: () -> Void

    var body: some View {
        ZStack {
            Text(title).font(.headline).foregroundStyle(Color.fg)
            HStack {
                Button(action: back) {
                    Text("‹ Tilbage").font(.callout).foregroundStyle(Color.acc)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 14)
    }
}

/// Systemets delingsark (gem i Filer, AirDrop, mail …).
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// «Folke Plus»: status, køb og «Gendan køb» (PLAN.md afsnit 9).
struct PlusCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted
    /// I en liste (Indstillinger) står kortet uden egen baggrund
    var inList = false

    var body: some View {
        let status = model.snapshot.plus
        let shop = model.plusStore
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Folke Plus").font(.headline).foregroundStyle(Color.fg)
                Spacer()
                if status == .purchased { Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.acc) }
            }
            Text(status.text).font(.subheadline).foregroundStyle(Color.fg).padding(.top, 6)
            if status != .purchased {
                Text("Resten af dagen med en plan, der tilpasser sig korte og oversprungne lure, widgets, Live Activity, "
                     + "Siri og vækstkurver. Ét køb, intet abonnement, og det deles med familien. Søvn, mad, udpumpning, "
                     + "næste lur og sengetid, notifikationer, deling med partneren og alt, du har registreret, er altid gratis.")
                    .font(.footnote).foregroundStyle(muted).padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
                Button { Task { await shop.buy() } } label: {
                    Group {
                        if shop.busy {
                            ProgressView().tint(.white)
                        } else {
                            Text(shop.product.map { "Køb Folke Plus · \($0.displayPrice)" } ?? "Køb Folke Plus")
                        }
                    }
                    .font(.callout).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(12)
                    .background(Color.acc, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(shop.product == nil || shop.busy)
                .opacity(shop.product == nil ? 0.5 : 1)
                .padding(.top, 12)
                Button("Gendan køb") { Task { await shop.restore() } }
                    .font(.subheadline).foregroundStyle(muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .disabled(shop.busy)
            }
            if let m = shop.message {
                Text(m).font(.footnote).foregroundStyle(Color.errorText).padding(.top, 8)
            }
        }
        .modifier(OptionalCard(on: !inList))
    }
}

struct OptionalCard: ViewModifier {
    var on: Bool
    func body(content: Content) -> some View {
        if on { content.card() } else { content.padding(.vertical, 6) }
    }
}
