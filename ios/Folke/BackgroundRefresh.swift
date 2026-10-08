import BackgroundTasks
import FolkeCore
import Foundation

/// Baggrundsopdatering (`BGAppRefreshTask`): iOS vækker appen af og til, og så planlægges notifikationer, widgets og
/// Live Activity forfra, også når appen ikke har været åbnet, fx efter at partneren har registreret noget (milepæl 6).
/// iOS bestemmer selv hvornår; tidspunktet her er kun det tidligste.
enum BackgroundRefresh {
    static let id = "dk.folkeapp.folke.refresh"

    /// Bed om næste opvågning: senest 30 min frem, tidligere hvis «slap af» skal sendes før.
    @MainActor static func schedule(now: Date = .now) {
        var earliest = now.addingTimeInterval(30 * 60)
        if let p = FolkeShared.store.prediction(now: now) {
            let soon = p.time.addingTimeInterval(-Double(Notifier.leadMin + 10) * 60)
            if soon > now.addingTimeInterval(5 * 60) { earliest = min(earliest, soon) }
        }
        let r = BGAppRefreshTaskRequest(identifier: id)
        r.earliestBeginDate = earliest
        try? BGTaskScheduler.shared.submit(r)
    }

    @MainActor static func run() async {
        await FolkeSync.afterChange(FolkeShared.store)
        schedule()
    }
}
