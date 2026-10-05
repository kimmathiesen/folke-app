import CoreData
import FolkeCore
import Observation
import SwiftUI

/// Det, forsiden viser. Beregnes forfra, når data ændres (lokalt eller fra iCloud).
struct Snapshot {
    struct Item: Identifiable {
        var id: UUID
        var start: Date
        var end: Date
        var nap: Bool
    }

    var childName = ""
    var hasChild = false
    var running: Item?
    var awakeSince: Date?
    var prediction: Prediction?
    var today: [Item] = []
}

@MainActor @Observable
final class AppModel {
    /// iCloud-container. Slås til i milepæl 6, når appen signeres med udviklerkontoen.
    static let cloudKitContainer: String? = nil

    let store: FolkeStore
    private(set) var snapshot = Snapshot()
    var error: String?
    /// Lur/Nat-valg, mens søvnen kører (nil = gæt ud fra klokkeslættet)
    var napSelection: Bool?

    var role: Role? {
        didSet { UserDefaults.standard.set(role?.rawValue, forKey: "folke.role") }
    }

    init(store: FolkeStore) {
        self.store = store
        role = UserDefaults.standard.string(forKey: "folke.role").flatMap(Role.init(rawValue:))
        refresh()
        NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    static func live() -> AppModel {
        do {
            #if DEBUG
            // Skærmbilleder i simulatoren: start med `-demoData YES` for et barn på 4 mdr. og 10 dages søvn i hukommelsen
            if UserDefaults.standard.bool(forKey: "demoData") {
                let store = try FolkeStore(inMemory: true)
                try store.seedDemo()
                return AppModel(store: store)
            }
            #endif
            return AppModel(store: try FolkeStore(cloudKitContainer: cloudKitContainer))
        } catch {
            // Kan databasen ikke åbnes, kører appen i hukommelsen frem for at gå ned
            print("Core Data:", error)
            return AppModel(store: try! FolkeStore(inMemory: true))
        }
    }

    var needsOnboarding: Bool { !snapshot.hasChild || role == nil }

    func refresh(now: Date = .now) {
        let child = store.child()
        var s = Snapshot()
        s.hasChild = child != nil
        s.childName = child?.name ?? ""
        if let r = store.runningSleep(), let id = r.id, let start = r.start {
            s.running = .init(id: id, start: start, end: now, nap: r.nap)
        } else {
            napSelection = nil
        }
        s.awakeSince = store.awakeSince(now: now)
        s.prediction = store.prediction(now: now)
        s.today = store.todaySleeps(now: now).compactMap { x in
            guard let id = x.id, let start = x.start, let end = x.end else { return nil }
            return .init(id: id, start: start, end: end, nap: x.nap)
        }
        snapshot = s
    }

    /// Lur eller nat for den kørende søvn: brugerens valg, ellers gættet.
    var isNap: Bool {
        napSelection ?? snapshot.running.map { Predictor.napGuess($0.start) } ?? Predictor.napGuess(.now)
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            error = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        refresh()
    }

    func toggleSleep() {
        perform {
            if snapshot.running != nil {
                try store.stopSleep(nap: isNap)
            } else {
                try store.startSleep(by: role)
            }
        }
    }

    func finishOnboarding(name: String, birthDate: Date?, role: Role) {
        perform {
            if let child = store.child() {
                child.name = name
                try store.save()
            } else {
                try store.createChild(name: name, birthDate: birthDate ?? .now)
            }
            self.role = role
        }
    }
}
