import FolkeCore
import SwiftUI

/// Mad: registrér amning, flaske og fast føde, og se dagens måltider.
struct FoodPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.muted) private var muted

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tl in
            ScrollView {
                VStack(spacing: 16) {
                    PageTitle(title: "Mad").padding(.bottom, -16)
                    FeedCard(now: tl.date)
                    ErrorText()
                    today
                }
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .contentMargins(.horizontal, 18, for: .scrollContent)
            .contentMargins(.bottom, 20, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    @ViewBuilder var today: some View {
        let items = model.snapshot.feedItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("I dag").font(.system(size: 16, weight: .medium)).foregroundStyle(Color.fg)
                    Spacer()
                    Text(items.count == 1 ? "1 måltid" : "\(items.count) måltider")
                        .font(.system(size: 14)).foregroundStyle(muted)
                }
                .padding(.bottom, 4)
                ForEach(items) { x in
                    HStack(alignment: .firstTextBaseline) {
                        Text(Format.time(x.time)).monospacedDigit().foregroundStyle(Color.fg).frame(width: 52, alignment: .leading)
                        Text(describe(x)).foregroundStyle(muted)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 15))
                    .padding(.vertical, 9)
                    .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Slet", systemImage: "trash", role: .destructive) { model.deleteFeeding(id: x.id) }
                    }
                }
                Text("Hold fingeren på et måltid for at slette det.")
                    .font(.system(size: 12)).foregroundStyle(muted).padding(.top, 6)
            }
            .card()
        }
    }

    func describe(_ x: Snapshot.FeedItem) -> String {
        var parts = [Format.feedName(x.kind)]
        if x.amountMl > 0 { parts.append("\(Int(x.amountMl.rounded())) ml") }
        if x.kind == .bottle, x.milk == .formula { parts.append("erstatning") }
        if let n = x.note, !n.isEmpty { parts.append(n) }
        return parts.joined(separator: " · ")
    }
}
