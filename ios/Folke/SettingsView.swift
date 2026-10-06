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
    @FocusState private var nameFocused: Bool

    static let remindOptions: [(Double, String)] = [(2, "efter 2 t"), (2.5, "efter 2½ t"), (3, "efter 3 t"),
                                                     (3.5, "efter 3½ t"), (4, "efter 4 t"), (5, "efter 5 t"),
                                                     (6, "efter 6 t")]

    var body: some View {
        let s = model.snapshot
        ScrollView {
            VStack(spacing: 0) {
                BackHeader(title: "Indstillinger") { save(); model.page = .home }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Tilpas").font(.system(size: 18, weight: .medium)).foregroundStyle(Color.fg)

                    row("Barnets navn") {
                        TextField("", text: $name)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($nameFocused)
                            .onSubmit(save)
                            .font(.system(size: 15))
                            .padding(.vertical, 8).padding(.horizontal, 10)
                            .frame(width: 150)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.line))
                    }
                    row("Jeg er") {
                        menu(model.role, [(Role.mor, "Mor"), (.far, "Far")]) { model.role = $0 }
                    }
                    toggle("Amning i Mad-kortet", s.featureBreast) { model.setFeature(.breast, $0) }
                    toggle("Fast føde i Mad-kortet", s.featureSolids) { model.setFeature(.solids, $0) }
                    toggle("Udpumpning", s.featurePump) { model.setFeature(.pump, $0) }
                    if s.featurePump {
                        row("Påmind om udpumpning") {
                            menu(s.pumpRemindHours, Self.remindOptions) { model.setPumpRemind($0) }
                        }
                        note("Påmindelsen sendes kun til enheder, der har slået «Påmindelse om udpumpning» til under notifikationer herunder. Ingen påmindelser mellem 22 og 7.")
                    }

                    notifications

                    row("Vækstkurver") {
                        menu(s.sex, [(Sex.boy, "Dreng"), (.girl, "Pige")]) { model.setSex($0) }
                    }
                    toggle("Vis næste tøjstørrelse", model.showNextSize) { model.showNextSize = $0 }
                    note("Skøn ud fra sidste længdemåling på vækstsiden. Gælder kun denne enhed.")
                }
                .card()
                if !message.isEmpty {
                    Text(message).font(.system(size: 14)).foregroundStyle(Color.errorText).padding(.top, 12)
                }
            }
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .contentMargins(.horizontal, 18, for: .scrollContent)
        .contentMargins(.bottom, 28, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { name = s.childName }
        .onChange(of: nameFocused) { if !nameFocused { save() } }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await model.notifier.refreshStatus() } } }
    }

    /// Notifikationer på denne enhed: status, slå til, send test og beskedtyper.
    @ViewBuilder var notifications: some View {
        let n = model.notifier
        row("Notifikationer på denne enhed") {
            Text(n.status == .allowed ? "Slået til" : n.status == .denied ? "Blokeret" : "Slået fra")
            .font(.system(size: 14)).foregroundStyle(muted)
        }
        switch n.status {
        case .notAsked:
            ActionRow(options: [("Slå til", {
                Task {
                    message = await model.requestNotifications()
                        ? "" : "Notifikationer blev ikke tilladt"
                }
            })]).padding(.top, 10)
        case .denied:
            note("Tillad notifikationer for Folke under Indstillinger → Notifikationer.")
            ActionRow(options: [("Åbn Indstillinger", {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            })]).padding(.top, 10)
        case .allowed:
            ActionRow(options: [("Send test", { n.sendTest() })]).padding(.top, 10)
            note("Send til denne enhed:")
            toggle("Tid til at slappe af (\(NotificationPlanner.leadMin) min før)", n.enabled.contains(.sleepSoon)) {
                model.setNotification(.sleepSoon, $0)
            }
            toggle("Hvis lurtiden er gået (\(NotificationPlanner.overdueMin) min efter)", n.enabled.contains(.overdue)) {
                model.setNotification(.overdue, $0)
            }
            if model.snapshot.featurePump {
                toggle("Påmindelse om udpumpning", n.enabled.contains(.pump)) { model.setNotification(.pump, $0) }
            }
        case .unknown:
            EmptyView()
        }
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

    // Rækker som `.sw` i webappen: tekst til venstre, valg til højre
    func row<V: View>(_ label: String, @ViewBuilder _ trailing: () -> V) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.fg)
            Spacer(minLength: 12)
            trailing()
        }
        .font(.system(size: 16))
        .padding(.top, 12)
    }

    func toggle(_ label: String, _ on: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Toggle(label, isOn: Binding(get: { on }, set: set))
            .tint(Color.acc)
            .foregroundStyle(Color.fg)
            .font(.system(size: 16))
            .padding(.top, 12)
    }

    func menu<T: Hashable>(_ value: T?, _ options: [(T, String)], _ set: @escaping (T) -> Void) -> some View {
        Menu {
            ForEach(options, id: \.0) { v, label in
                Button { set(v) } label: { if v == value { Label(label, systemImage: "checkmark") } else { Text(label) } }
            }
        } label: {
            HStack(spacing: 4) {
                Text(options.first { $0.0 == value }?.1 ?? "Vælg")
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11))
            }
            .font(.system(size: 15))
            .foregroundStyle(Color.fg)
            .padding(.vertical, 8).padding(.horizontal, 10)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.line))
        }
    }

    func note(_ s: String) -> some View {
        Text(s).font(.system(size: 13)).foregroundStyle(muted).padding(.top, 6)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// «‹ Tilbage» med titel i midten (`.gh` i webappen).
struct BackHeader: View {
    var title: String
    var back: () -> Void

    var body: some View {
        ZStack {
            Text(title).font(.system(size: 18, weight: .medium)).foregroundStyle(Color.fg)
            HStack {
                Button(action: back) {
                    Text("‹ Tilbage").font(.system(size: 16)).foregroundStyle(Color.acc)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 14)
    }
}
