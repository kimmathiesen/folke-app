import FolkeCore
import Foundation

/// Det, appen, widgets og App Intents deler: App Group, databasen og indstillinger pr. enhed.
enum FolkeShared {
    static let appGroup = "group.dk.folkeapp.folke"
    /// iCloud-container. Slås til i milepæl 6, når appen signeres med udviklerkontoen.
    static let cloudKitContainer: String? = nil
    /// Indstillinger pr. enhed (rolle, beskedtyper, log over sendte beskeder), delt med widgets og intents
    nonisolated(unsafe) static let defaults = UserDefaults(suiteName: appGroup) ?? .standard
    /// Sendes, når en App Intent (Siri, widget, Live Activity) har ændret data, så appen opdaterer sig
    static let changed = Notification.Name("FolkeDataChanged")

    /// Databasen i App Group-mappen. Appen synkroniserer med iCloud (milepæl 6); widgets læser kun.
    @MainActor static var store: FolkeStore = {
        do {
            return try FolkeStore(cloudKitContainer: cloudKitContainer, appGroup: appGroup)
        } catch {
            print("Core Data:", error)
            return try! FolkeStore(inMemory: true)
        }
    }()

    /// Mor/far på denne enhed. Læser den gamle placering (før App Group), hvis den nye er tom.
    static var role: Role? {
        get {
            (defaults.string(forKey: "folke.role") ?? UserDefaults.standard.string(forKey: "folke.role"))
                .flatMap(Role.init(rawValue:))
        }
        set { defaults.set(newValue?.rawValue, forKey: "folke.role") }
    }
}
