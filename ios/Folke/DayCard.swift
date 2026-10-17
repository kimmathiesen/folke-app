import FolkeCore
import SwiftUI

/// Dagens søvn (`#day`): tidslinje med varighed og samlet søvn. Tryk for at rette eller slette.
struct DayCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted
    @State private var editing: Snapshot.Item?
    var now: Date

    var body: some View {
        let items = model.snapshot.today
        let mins = items.map { $0.sleptMinutes() }
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 12) {
                    CardIcon(name: "calendar", size: 26)
                    Text("Dagens søvn").font(.headline).foregroundStyle(Color.fg)
                }
                Spacer()
                Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalizedFirst)
                    .font(.subheadline).foregroundStyle(muted)
            }
            .padding(.bottom, 16)

            VStack(spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, x in
                    let napNo = items[...i].filter(\.nap).count
                    Button { editing = x } label: { row(x, label: x.nap ? "Lur \(napNo)" : nightLabel(x), minutes: mins[i]) }
                        .buttonStyle(.plain)
                }
            }
            .background(alignment: .leading) {
                // Lodret linje i døgnets farver
                LinearGradient(stops: [.init(color: Color(hex: "#e0a63c"), location: 0),
                                       .init(color: Color(hex: "#3f9be0"), location: 0.4),
                                       .init(color: Color(hex: "#e8814f"), location: 0.7),
                                       .init(color: Color(hex: "#7c6ff0"), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: 2)
                    .clipShape(Capsule())
                    .padding(.vertical, 24)
                    .padding(.leading, 6)
            }

            HStack {
                Text("Samlet søvn").foregroundStyle(muted)
                Spacer()
                Text(Format.duration(minutes: mins.reduce(0, +))).fontWeight(.medium).foregroundStyle(Color.fg)
            }
            .padding(.top, 12)
            .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
            .padding(.top, 6)
            .padding(.horizontal, 4)
        }
        .card()
        .sheet(item: $editing) { x in
            EditSleepSheet(item: x)
        }
    }

    /// «Nat · 2 opvågninger · 25 min vågen»
    func nightLabel(_ x: Snapshot.Item) -> String {
        guard !x.wakes.isEmpty else { return "Nat" }
        let n = x.wakes.count, m = Int(x.wakes.reduce(0) { $0 + $1.minutes() }.rounded())
        return "Nat · \(n) \(n == 1 ? "opvågning" : "opvågninger") · \(Format.duration(minutes: m)) vågen"
    }

    func row(_ x: Snapshot.Item, label: String, minutes: Int) -> some View {
        let part = DayPart.of(start: x.start, nap: x.nap)
        let c = Color(part.color)
        return HStack(spacing: 12) {
            Image(systemName: part == .night ? "moon" : part == .day ? "sun.max" : "sunrise")
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(c, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Format.time(x.start)) – \(Format.time(x.end))").font(.body).monospacedDigit()
                    .foregroundStyle(Color.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(label).font(.subheadline).foregroundStyle(muted)
            }
            Spacer(minLength: 0)
            Text(Format.duration(minutes: minutes))
                .font(.subheadline).foregroundStyle(muted)
                .padding(.vertical, 6).padding(.horizontal, 12)
                .background(Color.white.opacity(0.07), in: Capsule())
                .fixedSize()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(muted)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.line))
        .contentShape(Rectangle())
        .padding(.leading, 22)
        .overlay(alignment: .leading) { Circle().fill(c).frame(width: 10, height: 10).padding(.leading, 2) }
    }
}

/// «Ret søvn» (`#sheet`): start, slut, lur/nat, varighed. Sletning kræver to tryk.
struct EditSleepSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.muted) private var muted
    @State private var start: Date
    @State private var end: Date
    @State private var nap: Bool?
    @State private var armed = false
    @State private var error = ""
    @State private var wakes: [WakeItem]
    /// nil = «Tilføj søvn» (en glemt søvn, fx en nat), ellers «Ret søvn»
    let item: Snapshot.Item?

    init(item: Snapshot.Item) {
        self.item = item
        _start = State(initialValue: item.start)
        _end = State(initialValue: item.end)
        _nap = State(initialValue: item.nap)
        _wakes = State(initialValue: item.wakes)
    }

    init(addStart: Date, end: Date, nap: Bool) {
        item = nil
        _start = State(initialValue: addStart)
        _end = State(initialValue: end)
        _nap = State(initialValue: nap)
        _wakes = State(initialValue: [])
    }

    var body: some View {
        let m = Int((end.timeIntervalSince(start) / 60).rounded())
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(item == nil ? "Tilføj søvn" : "Ret søvn").font(.headline).foregroundStyle(Color.fg)
                field("Faldt i søvn", $start)
                field("Vågnede", $end)
                Segmented(options: [(true, "Lur"), (false, "Nat")], selection: $nap).padding(.top, 12)
                Text(m > 0 ? "Varighed: \(Format.duration(minutes: m))" : "Sluttid skal være efter starttid")
                    .font(.subheadline).foregroundStyle(muted).padding(.top, 12)
                if !wakes.isEmpty {
                    Text("Opvågninger").font(.subheadline).foregroundStyle(muted).padding(.top, 12)
                    ForEach(wakes) { w in
                        HStack {
                            Text("\(Format.time(w.start)) – \(w.end.map { Format.time($0) } ?? "nu")")
                                .foregroundStyle(Color.fg)
                            Spacer()
                            Button("Slet") {
                                model.deleteWake(id: w.id)
                                wakes.removeAll { $0.id == w.id }
                            }
                            .foregroundStyle(Color.errorText)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 6)
                        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
                    }
                }
                if !error.isEmpty {
                    Text(error).font(.subheadline).foregroundStyle(Color.errorText).padding(.top, 12)
                }
                VStack(spacing: 10) {
                    GoButton(title: item == nil ? "Gem søvn" : "Gem ændringer") {
                        let e = item.map { model.editSleep(id: $0.id, start: start, end: end, nap: nap ?? true) }
                            ?? model.addSleep(start: start, end: end, nap: nap ?? true)
                        if let e { error = e } else { dismiss() }
                    }
                    if let item {
                        GoButton(title: armed ? "Tryk igen for at slette" : "Slet søvn", kind: .delete) {
                            if !armed { return armed = true }
                            model.deleteSleep(id: item.id)
                            dismiss()
                        }
                    }
                    GoButton(title: "Annullér", kind: .ghost) { dismiss() }
                }
                .padding(.top, 10)
            }
            .padding(20)
        }
        .onChange(of: start) { armed = false }
        .onChange(of: end) { armed = false }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(hex: "#131c36"))
        .presentationCornerRadius(24)
        .preferredColorScheme(.dark)
    }

    func field(_ label: String, _ value: Binding<Date>) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(muted)
            Spacer()
            DatePicker(label, selection: value, in: ...Date.now).labelsHidden()
        }
        .padding(.top, 14)
    }
}

extension String {
    /// Stort begyndelsesbogstav («Mandag 5. oktober»), som `cap` i index.html.
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// «Tilføj glemt søvn» under Dagens søvn, og kortet «Mangler natten?» (`#sadd` og `#miss` i index.html).
struct AddSleepButton: View {
    @State private var adding: (start: Date, end: Date, nap: Bool)?
    @State private var addID = UUID()

    var body: some View {
        GoButton(title: "Tilføj glemt søvn", kind: .ghost) {
            addID = UUID()
            adding = (.now.addingTimeInterval(-3600), .now, true)
        }
        .sheet(isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } })) {
            if let a = adding { EditSleepSheet(addStart: a.start, end: a.end, nap: a.nap).id(addID) }
        }
    }
}

struct MissingNightCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted
    @State private var adding = false
    var night: (start: Date, end: Date)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Mangler natten?").font(.callout.weight(.medium)).foregroundStyle(Color.fg)
            Text("Der er ingen nat registreret fra i går aftes. Tilføj den, så planen for i dag passer igen.")
                .font(.subheadline).foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            ActionRow(options: [("Tilføj natten", { adding = true }),
                                ("Ikke nu", { model.missSeen = AppModel.dayKey(.now) })])
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .sheet(isPresented: $adding) { EditSleepSheet(addStart: night.start, end: night.end, nap: false) }
    }
}
