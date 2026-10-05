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
        let mins = items.map { Int(($0.end.timeIntervalSince($0.start) / 60).rounded()) }
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 12) {
                    CardIcon(name: "calendar", size: 26)
                    Text("Dagens søvn").font(.system(size: 18, weight: .medium)).foregroundStyle(Color.fg)
                }
                Spacer()
                Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalizedFirst)
                    .font(.system(size: 14)).foregroundStyle(muted)
            }
            .padding(.bottom, 16)

            VStack(spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, x in
                    let napNo = items[...i].filter(\.nap).count
                    Button { editing = x } label: { row(x, label: x.nap ? "Lur \(napNo)" : "Nat", minutes: mins[i]) }
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

    func row(_ x: Snapshot.Item, label: String, minutes: Int) -> some View {
        let part = DayPart.of(start: x.start, nap: x.nap)
        let c = Color(part.color)
        return HStack(spacing: 12) {
            Image(systemName: part == .night ? "moon" : part == .day ? "sun.max" : "sunrise")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(c, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Format.time(x.start)) – \(Format.time(x.end))").font(.system(size: 17)).monospacedDigit()
                    .foregroundStyle(Color.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(label).font(.system(size: 14)).foregroundStyle(muted)
            }
            Spacer(minLength: 0)
            Text(Format.duration(minutes: minutes))
                .font(.system(size: 14)).foregroundStyle(muted)
                .padding(.vertical, 6).padding(.horizontal, 12)
                .background(Color.white.opacity(0.07), in: Capsule())
                .fixedSize()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(muted)
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
    let item: Snapshot.Item

    init(item: Snapshot.Item) {
        self.item = item
        _start = State(initialValue: item.start)
        _end = State(initialValue: item.end)
        _nap = State(initialValue: item.nap)
    }

    var body: some View {
        let m = Int((end.timeIntervalSince(start) / 60).rounded())
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ret søvn").font(.system(size: 18, weight: .medium)).foregroundStyle(Color.fg)
                field("Faldt i søvn", $start)
                field("Vågnede", $end)
                Segmented(options: [(true, "Lur"), (false, "Nat")], selection: $nap).padding(.top, 12)
                Text(m > 0 ? "Varighed: \(Format.duration(minutes: m))" : "Sluttid skal være efter starttid")
                    .font(.system(size: 14)).foregroundStyle(muted).padding(.top, 12)
                if !error.isEmpty {
                    Text(error).font(.system(size: 14)).foregroundStyle(Color.errorText).padding(.top, 12)
                }
                VStack(spacing: 10) {
                    GoButton(title: "Gem ændringer") {
                        if let e = model.editSleep(id: item.id, start: start, end: end, nap: nap ?? true) {
                            error = e
                        } else {
                            dismiss()
                        }
                    }
                    GoButton(title: armed ? "Tryk igen for at slette" : "Slet søvn", kind: .delete) {
                        if !armed { return armed = true }
                        model.deleteSleep(id: item.id)
                        dismiss()
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
            Text(label).font(.system(size: 14)).foregroundStyle(muted)
            Spacer()
            DatePicker(label, selection: value).labelsHidden()
        }
        .padding(.top, 14)
    }
}

extension String {
    /// Stort begyndelsesbogstav («Mandag 5. oktober»), som `cap` i index.html.
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
