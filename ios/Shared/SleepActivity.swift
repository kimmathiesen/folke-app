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
}

@MainActor enum SleepLiveActivity {
    /// Start, opdatér eller afslut, så den passer med den kørende søvn. Startes på den enhed, der ser søvnen
    /// (også når den anden forælder har startet den, og ændringen kommer fra iCloud, mens appen er åben).
    static func sync(running: (start: Date, nap: Bool)?, name: String, expectedWake: Date?) async {
        let state = running.map {
            SleepActivityAttributes.ContentState(start: $0.start, nap: $0.nap, expectedWake: $0.nap ? expectedWake : nil)
        }
        let current = Activity<SleepActivityAttributes>.activities
        if let state, current.isEmpty {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            _ = try? Activity.request(attributes: SleepActivityAttributes(childName: name),
                                      content: ActivityContent(state: state, staleDate: nil))
            return
        }
        // Afventes, så en App Intent (fx «Stop søvn» i Dynamic Island) når at afslutte, før appen lægges i baggrunden
        for (i, a) in current.enumerated() {
            if let state, i == 0 {
                if a.content.state != state { await a.update(ActivityContent(state: state, staleDate: nil)) }
            } else {
                await a.end(ActivityContent(state: a.content.state, staleDate: nil), dismissalPolicy: .immediate)
            }
        }
    }
}
