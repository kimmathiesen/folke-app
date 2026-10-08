import CloudKit
import CoreData
import Foundation

/// Core Data med iCloud (`NSPersistentCloudKitContainer`): en privat store (ens egne data) og en delt store
/// (familien, som partneren har delt med en). Uden `cloudKitContainer` kører alt lokalt (tests, simulator uden konto).
public final class FolkeStore: @unchecked Sendable {
    public let container: NSPersistentCloudKitContainer
    public private(set) var privateStore: NSPersistentStore?
    public private(set) var sharedStore: NSPersistentStore?
    public var calendar: Calendar = .current
    /// Barnet, der vises på denne enhed (gemmes af appen pr. enhed). nil = det ældste.
    public var currentChildID: UUID?

    public var context: NSManagedObjectContext { container.viewContext }

    /// - Parameters:
    ///   - inMemory: kun i hukommelsen (tests og forhåndsvisninger)
    ///   - cloudKitContainer: fx "iCloud.dk.folkeapp.folke". nil = ingen iCloud
    ///   - appGroup: deles med widgets og App Intents
    ///   - directory: en bestemt mappe til databasen (tests af opgradering)
    public init(inMemory: Bool = false, cloudKitContainer: String? = nil, appGroup: String? = nil,
                directory: URL? = nil) throws {
        container = NSPersistentCloudKitContainer(name: "Folke", managedObjectModel: FolkeModel.shared)

        let dir: URL
        if inMemory {
            dir = URL(fileURLWithPath: "/dev/null")
        } else if let directory {
            dir = directory
        } else if let appGroup, let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            dir = url
        } else {
            dir = NSPersistentContainer.defaultDirectoryURL()
        }
        func description(_ file: String) -> NSPersistentStoreDescription {
            let d = NSPersistentStoreDescription(url: inMemory ? dir : dir.appendingPathComponent(file))
            if inMemory { d.type = NSInMemoryStoreType }
            d.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            d.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            return d
        }
        var descriptions = [description("Folke.sqlite")]
        if let cloudKitContainer {
            descriptions[0].cloudKitContainerOptions = .init(containerIdentifier: cloudKitContainer)
            let shared = description("Folke-shared.sqlite")
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainer)
            options.databaseScope = .shared
            shared.cloudKitContainerOptions = options
            descriptions.append(shared)
        }
        container.persistentStoreDescriptions = descriptions
        if !inMemory {
            for d in descriptions { if let url = d.url { try Self.migrateIfNeeded(url) } }
        }

        var failure: Error?
        container.loadPersistentStores { _, error in
            if let error { failure = error }
        }
        if let failure { throw failure }
        let stores = container.persistentStoreCoordinator.persistentStores
        privateStore = stores.first
        sharedStore = stores.count > 1 ? stores[1] : nil

        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        try ensureFamily()
    }

    /// Version 1 -> 2 (familien). Modellen er bygget i kode, så Core Data kan ikke selv finde den gamle model:
    /// den gamle bygges her, og flytningen udledes (kun nye felter og relationer). Data rykkes til familien i `ensureFamily`.
    static func migrateIfNeeded(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let options: [String: Any] = [NSPersistentHistoryTrackingKey: true]
        let meta = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url, options: options)
        let new = FolkeModel.shared
        if new.isConfiguration(withName: nil, compatibleWithStoreMetadata: meta) { return }
        let old = FolkeModel.build(version: 1)
        guard old.isConfiguration(withName: nil, compatibleWithStoreMetadata: meta) else { return }
        let mapping = try NSMappingModel.inferredMappingModel(forSourceModel: old, destinationModel: new)
        let tmp = url.deletingLastPathComponent().appendingPathComponent("Folke-opgradering.sqlite")
        let psc = NSPersistentStoreCoordinator(managedObjectModel: new)
        func removeTmp() {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: tmp.path + suffix))
            }
        }
        removeTmp()
        defer { removeTmp() }
        try NSMigrationManager(sourceModel: old, destinationModel: new)
            .migrateStore(from: url, type: .sqlite, options: options, mapping: mapping, to: tmp, type: .sqlite, options: options)
        try psc.replacePersistentStore(at: url, destinationOptions: options, withPersistentStoreFrom: tmp,
                                       sourceOptions: options, type: .sqlite)
    }

    /// Alle børn hører til én familie, og udpumpning og tavlen ligger på familien. Retter data fra version 1
    /// (og børn uden familie) ved opstart. Udpumpningsvalgene tages fra barnets gamle indstillinger.
    func ensureFamily(now: Date = .now) throws {
        let children = fetch(Child.self, sort: [NSSortDescriptor(key: "createdAt", ascending: true)])
        guard !children.isEmpty else { return }
        let fam = family() ?? {
            let f = insert(Family.self, child: children[0])
            f.id = UUID()
            f.createdAt = children[0].createdAt ?? now
            if let old = fetch(Settings.self, sort: [NSSortDescriptor(key: "createdAt", ascending: true)], limit: 1).first {
                f.featurePump = old.featurePump
                f.pumpRemindHours = old.pumpRemindHours
            }
            return f
        }()
        for c in children where c.family == nil { c.family = fam }
        for p in fetch(Pumping.self, NSPredicate(format: "family == nil")) { p.family = fam; p.child = nil }
        for s in fetch(Stroke.self, NSPredicate(format: "family == nil")) { s.family = fam; s.child = nil }
        try save()
    }

    public func save() throws {
        if context.hasChanges { try context.save() }
    }

    func fetch<T: NSManagedObject>(_ type: T.Type, _ predicate: NSPredicate? = nil,
                                   sort: [NSSortDescriptor] = [], limit: Int = 0) -> [T] {
        let r = NSFetchRequest<T>(entityName: String(describing: type))
        r.predicate = predicate
        r.sortDescriptors = sort
        r.fetchLimit = limit
        return (try? context.fetch(r)) ?? []
    }

    /// Nye poster skal ligge i samme store som barnet (den delte, hvis familien er delt med os).
    func insert<T: NSManagedObject>(_ type: T.Type, child: Child?) -> T {
        let obj = T(context: context)
        if let store = child?.objectID.persistentStore ?? privateStore {
            context.assign(obj, to: store)
        }
        return obj
    }

    /// Sletter alt (kun til demo-data i debug-builds og tests).
    public func deleteAll() throws {
        for e in FolkeModel.shared.entities {
            let r = NSFetchRequest<NSManagedObject>(entityName: e.name!)
            for o in try context.fetch(r) { context.delete(o) }
        }
        try save()
    }

    // MARK: Familie, børn og indstillinger

    /// Familien (den ældste, hvis to telefoner har oprettet hver sin).
    public func family() -> Family? {
        fetch(Family.self, sort: [NSSortDescriptor(key: "createdAt", ascending: true)], limit: 1).first
    }

    /// Alle børn, ældste først (efter fødselsdato).
    public func children() -> [Child] {
        fetch(Child.self, sort: [NSSortDescriptor(key: "birthDate", ascending: true),
                                 NSSortDescriptor(key: "createdAt", ascending: true)])
    }

    /// Barnet, der vises: det valgte på denne enhed, ellers det først oprettede.
    public func child() -> Child? {
        if let currentChildID,
           let c = fetch(Child.self, NSPredicate(format: "id == %@", currentChildID as CVarArg), limit: 1).first {
            return c
        }
        return fetch(Child.self, sort: [NSSortDescriptor(key: "createdAt", ascending: true)], limit: 1).first
    }

    /// Kun det valgte barns poster (søvn, mad, vækst, indstillinger). Uden barn: ingen.
    func forChild(_ p: NSPredicate? = nil) -> NSPredicate {
        guard let c = child() else { return NSPredicate(value: false) }
        let mine = NSPredicate(format: "child == %@", c)
        return p.map { NSCompoundPredicate(andPredicateWithSubpredicates: [mine, $0]) } ?? mine
    }

    /// Kun familiens poster (udpumpning, tavlen).
    func forFamily(_ p: NSPredicate? = nil) -> NSPredicate {
        guard let f = family() else { return NSPredicate(value: false) }
        let mine = NSPredicate(format: "family == %@", f)
        return p.map { NSCompoundPredicate(andPredicateWithSubpredicates: [mine, $0]) } ?? mine
    }

    /// Opret et barn i familien (og familien, hvis det er det første). Det nye barn bliver det valgte.
    @discardableResult
    public func createChild(name: String, birthDate: Date, sex: Sex = .boy, now: Date = .now) throws -> Child {
        let fam = family() ?? {
            let f = insert(Family.self, child: nil)
            f.id = UUID()
            f.createdAt = now
            return f
        }()
        let c = insert(Child.self, child: nil)
        if let store = fam.objectID.persistentStore { context.assign(c, to: store) }
        c.family = fam
        c.id = UUID()
        c.name = name
        c.birthDate = calendar.startOfDay(for: birthDate)
        c.sex = sex.rawValue
        c.createdAt = now
        let s = insert(Settings.self, child: c)
        s.id = UUID()
        s.createdAt = now
        // Startvalg efter alder (fx en storesøster): fast føde fra 6 mdr., amning under 12 mdr.
        let months = WHO.ageMonths(birthDate: birthDate, at: now, calendar: calendar)
        s.featureSolids = months >= 6
        s.featureBreast = months < 12
        s.child = c
        try save()
        currentChildID = c.id
        return c
    }

    /// Slet et barn med alle dets data. Udpumpning og tavlen (familiens) bliver.
    public func deleteChild(_ c: Child) throws {
        if c.id == currentChildID { currentChildID = nil }
        context.delete(c)
        try save()
    }

    /// Det valgte barns indstillinger (den ældste, hvis to telefoner har oprettet hver sin).
    public func settings() -> Settings? {
        fetch(Settings.self, forChild(), sort: [NSSortDescriptor(key: "createdAt", ascending: true)], limit: 1).first
    }

    // MARK: Søvn

    /// Den kørende søvn (uden slut), hvis der er en.
    public func runningSleep() -> Sleep? {
        fetch(Sleep.self, forChild(NSPredicate(format: "end == nil")),
              sort: [NSSortDescriptor(key: "start", ascending: false)], limit: 1).first
    }

    /// Afsluttede søvn, der sluttede efter `since`, sorteret efter start.
    public func sleeps(since: Date) -> [Sleep] {
        fetch(Sleep.self, forChild(NSPredicate(format: "end != nil AND end >= %@", since as NSDate)),
              sort: [NSSortDescriptor(key: "start", ascending: true)])
    }

    public func lastSleepEnd(now: Date) -> Date? {
        sleeps(since: now.addingTimeInterval(-3 * 86400)).compactMap(\.end).max()
    }

    /// Start søvn nu eller på et tidligere tidspunkt («Faldt i søvn kl.»). Kører der allerede en, sker der intet.
    @discardableResult
    public func startSleep(at start: Date? = nil, by role: Role?, now: Date = .now) throws -> Sleep {
        if let running = runningSleep() { return running }
        let st = start ?? now
        if start != nil {
            try SleepRules.checkStart(st, previousEnd: lastSleepEnd(now: now))
        }
        let c = child()
        let s = insert(Sleep.self, child: c)
        s.id = UUID()
        s.start = st
        s.nap = Predictor.napGuess(st, calendar: calendar)
        s.createdBy = role?.rawValue
        s.child = c
        try save()
        return s
    }

    /// Stop den kørende søvn nu eller på et tidligere tidspunkt («Vågnede kl.»).
    public func stopSleep(at end: Date? = nil, nap: Bool? = nil, now: Date = .now) throws {
        guard let s = runningSleep(), let start = s.start else { return }
        let e = end ?? now
        if end != nil {
            try SleepRules.checkWake(e, start: start)
        }
        s.end = max(e, start)
        // Har brugeren ikke selv valgt lur/nat, gættes der ud fra både start og længde (aftenlur efter kl. 18 = lur)
        s.nap = nap ?? DayPlanner.napAtStop(start: start, end: s.end ?? e, calendar: calendar)
        try save()
    }

    /// Forudsigelsen er slået til for barnet (kan skjules, når barnet er holdt op med at sove lur)
    var predictionOn: Bool { settings()?.featurePrediction ?? true }

    public func prediction(now: Date = .now) -> Prediction? {
        guard predictionOn, runningSleep() == nil, let birth = child()?.birthDate else { return nil }
        let samples = sleeps(since: now.addingTimeInterval(-Double(Predictor.historyDays) * 86400)).compactMap(\.sample)
        return Predictor.predict(samples, birthDate: birth, now: now, calendar: calendar)
    }

    /// Gratisudgaven: kun næste lur eller sengetid (`Predictor.basic`, den oprindelige forudsigelse).
    public func basicPrediction(now: Date = .now) -> Prediction? {
        guard predictionOn, runningSleep() == nil, let birth = child()?.birthDate else { return nil }
        let samples = sleeps(since: now.addingTimeInterval(-Double(Predictor.historyDays) * 86400)).compactMap(\.sample)
        return Predictor.basic(samples, birthDate: birth, now: now, calendar: calendar)
    }

    /// Resten af dagen (afsnit 3). Under en lur regnes planen fra forventet opvågning; om natten er der ingen plan.
    public func dayPlan(now: Date = .now) -> DayPlan? {
        guard predictionOn, let birth = child()?.birthDate else { return nil }
        let running = runningSleep()?.start
        if let running, !Predictor.napGuess(running, calendar: calendar) { return nil }
        let samples = sleeps(since: now.addingTimeInterval(-Double(Predictor.historyDays) * 86400)).compactMap(\.sample)
        return DayPlanner.plan(samples, birthDate: birth, now: now, running: running, calendar: calendar)
    }

    /// Dagens søvn til ringen og listen: dem, der starter eller slutter i dag.
    public func todaySleeps(now: Date = .now) -> [Sleep] {
        let today = calendar.startOfDay(for: now)
        return sleeps(since: today).filter { s in
            [s.start, s.end].contains { $0.map { calendar.isDate($0, inSameDayAs: today) } ?? false }
        }
    }

    /// Vågen siden: slut på seneste søvn.
    public func awakeSince(now: Date = .now) -> Date? {
        sleeps(since: now.addingTimeInterval(-Double(Predictor.historyDays) * 86400)).compactMap(\.end).max()
    }
}
