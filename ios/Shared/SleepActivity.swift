import ActivityKit
import FolkeCore
import Foundation

/// Live Activity for en kørende søvn: låseskærm og Dynamic Island (milepæl 7).
/// Tælleren er `Text(timerInterval:)`, så den kører uden opdateringer fra en server.
struct SleepActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var start: Date
        var nap: Bool
        /// Forventet opvågning ud fra hans lure (kun ved lur)
        var expectedWake: Date?
    }

    var childName: String
    /// Barnets id, så hvert sovende barn har sin egen Live Activity
    var childID: String = ""
}

@MainActor enum SleepLiveActivity {
    /// En kørende søvn for ét barn
    struct Entry: Equatable {
        var childID: String
        var name: String
        var state: SleepActivityAttributes.ContentState
    }

    /// Kørende søvn for alle børn (tvillinger kan sove samtidig), med forventet opvågning ved lur.
    static func entries(store: FolkeStore, now: Date = .now) -> [Entry] {
        let saved = store.currentChildID
        defer { store.currentChildID = saved }
        return store.children().compactMap { c in
            store.currentChildID = c.id
            guard let id = c.id, let r = store.runningSleep(), let start = r.start else { return nil }
            let wake = r.nap ? store.dayPlan(now: now)?.wake : nil
            return Entry(childID: id.uuidString, name: c.name ?? "",
                         state: .init(start: start, nap: r.nap, expectedWake: wake))
        }
    }

    /// Én Live Activity pr. sovende barn: start, opdatér eller afslut, så de passer med de kørende søvn.
    /// Startes på den enhed, der ser søvnen (også når den anden forælder har startet den, og ændringen kommer fra iCloud).
    /// Kræver Folke Plus.
    static func sync(_ entries: [Entry]) async {
        let entries = FolkeShared.plus().unlocked ? entries : []
        let current = Activity<SleepActivityAttributes>.activities
        // Afventes, så en App Intent (fx «Stop søvn» i Dynamic Island) når at afslutte, før appen lægges i baggrunden
        var seen = Set<String>()
        for a in current {
            if let e = entries.first(where: { $0.childID == a.attributes.childID }), !seen.contains(e.childID) {
                seen.insert(e.childID)
                if a.content.state != e.state { await a.update(ActivityContent(state: e.state, staleDate: nil)) }
            } else {
                await a.end(ActivityContent(state: a.content.state, staleDate: nil), dismissalPolicy: .immediate)
            }
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        for e in entries where !seen.contains(e.childID) {
            _ = try? Activity.request(attributes: SleepActivityAttributes(childName: e.name, childID: e.childID),
                                      content: ActivityContent(state: e.state, staleDate: nil))
        }
    }
}
