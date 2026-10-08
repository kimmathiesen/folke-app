import CoreData
import FolkeCore
import Observation
import StoreKit
import SwiftUI
import WidgetKit

/// Det, forsiden viser. Beregnes forfra, når data ændres (lokalt eller fra iCloud).
struct Snapshot {
    struct Item: Identifiable {
        var id: UUID
        var start: Date
        var end: Date
        var nap: Bool
        /// Opvågninger om natten
        var wakes: [WakeItem] = []

        /// Minutter sovet (uden opvågningerne)
        func sleptMinutes(now: Date = .now) -> Int {
            Int((end.timeIntervalSince(start) / 60 - wakes.reduce(0) { $0 + $1.minutes(now: now) }).rounded())
        }
    }

    var childName = ""
    var hasChild = false
    var running: Item?
    var awakeSince: Date?
    var prediction: Prediction?
    var plan: DayPlan?
    var today: [Item] = []
    var featureBreast = true
    var featureSolids = false
    var featurePump = true
    var lastFeed: (kind: FeedKind, amountMl: Double, time: Date)?
    var pump = PumpSummary(todayCount: 0, todayMl: 0, last: nil)
    var suggestion: Suggestions.Suggestion?
    var pumpRemindHours = 3.0
    var sex = Sex.boy
    var birthDate: Date?
    var growth: [GrowthPoint] = []
    var pumpHistory = PumpHistory(days: [], avgMl: nil)
    var pumpItems: [PumpItem] = []
    var clothing: ClothingEstimate?
    var strokes: [BoardStroke] = []
    var boardVersion = 0.0
    var plus = Plus.Status.trial(daysLeft: Plus.trialDays)
    var feedItems: [FeedItem] = []
    var featurePrediction = true
    /// Hvor godt forudsigelsen har ramt de seneste 14 dage (interval på kortet)
    var accuracy: Backtest.Summary?
    /// Alle børn (ældste først) og det valgte
    var children: [ChildItem] = []
    var childID: UUID?
    /// Tvillinger (samme fødselsdato som det valgte barn) og hvornår de faldt i søvn (nil = vågen)
    var twins: [TwinItem] = []

    struct TwinItem: Identifiable {
        var id: UUID
        var name: String
        var since: Date?
    }

    struct ChildItem: Identifiable, Hashable {
        var id: UUID
        var name: String
        var birthDate: Date
    }

    struct FeedItem: Identifiable {
        var id: UUID
        var time: Date
        var kind: FeedKind
        var amountMl: Double
        var milk: Milk?
        var note: String?
    }

    struct PumpItem: Identifiable {
        var id: UUID
        var time: Date
        var amountMl: Double
        var side: Side?
        var minutes: Double
    }
}

@MainActor @Observable
final class AppModel {
    let store: FolkeStore
    let notifier = Notifier()
    let plusStore = PlusStore()
    private(set) var snapshot = Snapshot()
    var error: String?
    /// Lur/Nat-valg, mens søvnen kører (nil = gæt ud fra klokkeslættet)
    var napSelection: Bool?
    /// Siden, der vises (som hash-ruterne i webappen)
    var page: Page = .home

    enum Page { case home, settings, board }

    /// Forsidens sider, man stryger mellem (som iPhones hjemmeskærm). Søvn er standard.
    enum Tab: Hashable, CaseIterable {
        case sleep, food, pump, growth

        var title: String {
            switch self {
            case .sleep: "Søvn"
            case .food: "Mad"
            case .pump: "Udpumpning"
            case .growth: "Vækst"
            }
        }
    }

    var tab: Tab = .sleep
    /// Udpumpning vises kun, når funktionen er slået til
    var tabs: [Tab] { Tab.allCases.filter { $0 != .pump || snapshot.featurePump } }

    var role: Role? {
        didSet { FolkeShared.role = role }
    }

    /// Import fra Folke-serveren vises kun i egne builds (Xcode, TestFlight), aldrig i App Store-udgaven.
    private(set) var importAvailable = false

    init(store: FolkeStore) {
        self.store = store
        role = FolkeShared.role
        if FolkeShared.trialStart == nil { FolkeShared.trialStart = .now }
        refresh()
        plusStore.onChange = { [weak self] in self?.refresh() }
        Task {
            await notifier.refreshStatus()
            refresh()
        }
        Task { importAvailable = await Self.isOwnBuild() }
        NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // En App Intent (Siri, widget, Live Activity) har ændret data i appens proces
        NotificationCenter.default.addObserver(forName: FolkeShared.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store.context.refreshAllObjects()
                self?.refresh()
            }
        }
    }

    /// Appens model på den fælles database i App Group (deles med widgets og App Intents).
    static func live() -> AppModel {
        #if DEBUG
        // Skærmbilleder i simulatoren. NB: databasen tømmes først, så widgets ser de samme data.
        // `-demoData YES` (evt. `-demoMonths 7`): barn på 4 mdr. med 10 dages søvn, mad, udpumpning og vækst.
        // `-demoExport <sti>`: en eksport fra Folke-serveren (som importen under Indstillinger).
        let d = UserDefaults.standard
        if d.string(forKey: "demoExport") != nil || d.bool(forKey: "demoData") {
            let store = FolkeShared.store
            do {
                try store.deleteAll()
                if let path = d.string(forKey: "demoExport") {
                    try store.importServerExport(Data(contentsOf: URL(fileURLWithPath: path)))
                } else {
                    let months = d.integer(forKey: "demoMonths")
                    try store.seedDemo(months: months > 0 ? months : 4, sibling: d.bool(forKey: "demoSibling"),
                                       twin: d.bool(forKey: "demoTwin"))
                    FolkeShared.childID = store.currentChildID
                }
            } catch {
                print("Demo:", error)
            }
        }
        #endif
        return AppModel(store: FolkeShared.store)
    }

    var needsOnboarding: Bool { !snapshot.hasChild || role == nil }

    func refresh(now: Date = .now) {
        let child = store.child()
        var s = Snapshot()
        s.hasChild = child != nil
        s.childName = child?.name ?? ""
        if let r = store.runningSleep(), let id = r.id, let start = r.start {
            s.running = .init(id: id, start: start, end: now, nap: r.nap, wakes: store.wakes(from: start))
        } else {
            napSelection = nil
        }
        s.awakeSince = store.awakeSince(now: now)
        s.plus = FolkeShared.plus(now: now)
        // Målingen regnes højst hvert 10. minut (og forfra ved skift af barn)
        if now.timeIntervalSince(accuracyAt) > 600 || accuracyChild != child?.id {
            accuracyCache = store.accuracy(plus: s.plus.unlocked, now: now)
            accuracyAt = now
            accuracyChild = child?.id
        }
        s.accuracy = accuracyCache
        // Gratis: den oprindelige forudsigelse (kun næste lur/sengetid). Plus: dagsplanen med løbende tilpasning.
        s.prediction = s.plus.unlocked ? store.prediction(now: now) : store.basicPrediction(now: now)
        s.plan = s.plus.unlocked ? store.dayPlan(now: now) : nil
        s.today = store.todaySleeps(now: now).compactMap { x in
            guard let id = x.id, let start = x.start, let end = x.end else { return nil }
            return .init(id: id, start: start, end: end, nap: x.nap, wakes: x.nap ? [] : store.wakes(from: start, to: end))
        }
        if let set = store.settings() {
            s.featureBreast = set.featureBreast
            s.featureSolids = set.featureSolids
            s.featurePrediction = set.featurePrediction
        }
        if let f = store.family() {
            s.featurePump = f.featurePump
            s.pumpRemindHours = f.pumpRemindHours
        }
        s.childID = child?.id
        s.twins = store.twinsSleepingSince().compactMap { t in
            t.child.id.map { .init(id: $0, name: t.child.name ?? "", since: t.since) }
        }
        s.children = store.children().compactMap { c in
            guard let id = c.id else { return nil }
            return .init(id: id, name: c.name ?? "", birthDate: c.birthDate ?? .now)
        }
        s.sex = child?.sex.flatMap(Sex.init(rawValue:)) ?? .boy
        if let f = store.lastFeeding(now: now), let t = f.time, let k = f.kind.flatMap(FeedKind.init(rawValue:)) {
            s.lastFeed = (k, f.amountMl, t)
        }
        s.pump = store.pumpSummary(now: now)
        s.feedItems = store.todayFeedings(now: now).compactMap { f in
            guard let id = f.id, let t = f.time, let k = f.kind.flatMap(FeedKind.init(rawValue:)) else { return nil }
            return .init(id: id, time: t, kind: k, amountMl: f.amountMl, milk: f.milk.flatMap(Milk.init(rawValue:)), note: f.note)
        }
        s.suggestion = store.suggestions(now: now).first
        s.birthDate = child?.birthDate
        s.growth = store.growthPoints()
        s.clothing = store.clothingEstimate(now: now)
        s.strokes = store.strokes()
        s.boardVersion = store.boardVersion()
        if page == .board { boardSeen = s.boardVersion }
        s.pumpHistory = store.pumpHistory(now: now)
        s.pumpItems = store.pumpings(since: now.addingTimeInterval(-7 * 86400)).reversed().compactMap { p in
            guard let id = p.id, let t = p.time else { return nil }
            return .init(id: id, time: t, amountMl: p.amountMl, side: p.side.flatMap(Side.init(rawValue:)), minutes: p.minutes)
        }
        snapshot = s
        if tab == .pump && !s.featurePump { tab = .sleep }
        syncExtensions(s)
        notifier.reschedule(store: store, now: now)
    }

    private var widgetKey = ""
    private var accuracyCache: Backtest.Summary?
    private var accuracyAt = Date.distantPast
    private var accuracyChild: UUID?

    /// Live Activity og widgets følger appen. Widgets genindlæses kun, når noget, de viser, har ændret sig.
    private func syncExtensions(_ s: Snapshot) {
        let entries = SleepLiveActivity.entries(store: store)
        Task { await SleepLiveActivity.sync(entries) }
        let key = [s.running?.start.description, s.awakeSince?.description,
                   s.plan?.items.map { $0.start.description }.joined(), s.childName, "\(s.plus.unlocked)",
                   s.childID?.uuidString].map { $0 ?? "-" }.joined(separator: "|")
        if key != widgetKey {
            widgetKey = key
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Lur eller nat for den kørende søvn: brugerens valg, ellers gættet.
    var isNap: Bool {
        napSelection ?? snapshot.running.map { Predictor.napGuess($0.start) } ?? Predictor.napGuess(.now)
    }

    /// Udfør en handling, vis en eventuel fejl, og opdatér forsiden. Giver true, hvis det lykkedes.
    @discardableResult
    private func perform(_ action: () throws -> Void) -> Bool {
        defer { refresh() }
        do {
            try action()
            error = nil
            return true
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func toggleSleep() {
        perform {
            if snapshot.running != nil {
                try store.stopSleep(nap: napSelection) // uden eget valg gættes ud fra start og længde
            } else {
                try store.startSleep(by: role)
            }
        }
    }

    /// Start søvn for det valgte barn og tvillingerne (dem, der ikke allerede sover)
    func startBoth() {
        perform { try store.startSleepWithTwins(by: role) }
    }

    /// Stop søvn for det valgte barn og tvillingerne
    func stopBoth() {
        perform { try store.stopSleepWithTwins() }
    }

    /// «Glemte du at trykke?»: faldt i søvn eller vågnede kl. (i går, hvis tidspunktet ligger i fremtiden).
    func forgot(_ time: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let t = SleepRules.resolve(hour: c.hour ?? 0, minute: c.minute ?? 0, now: .now)
        perform {
            if snapshot.running != nil {
                try store.stopSleep(at: t, nap: napSelection)
            } else {
                try store.startSleep(at: t, by: role)
            }
        }
    }

    /// Et valgfrit klokkeslæt («Tidspunkt (valgfrit)»): i dag, eller i går, hvis det ligger i fremtiden.
    static func resolve(_ time: Date?) -> Date? {
        time.map {
            let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
            return SleepRules.resolve(hour: c.hour ?? 0, minute: c.minute ?? 0, now: .now)
        }
    }

    func editSleep(id: UUID, start: Date, end: Date, nap: Bool) -> String? {
        guard let s = store.sleep(id: id) else { return nil }
        do {
            try store.editSleep(s, start: start, end: end, nap: nap)
            refresh()
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func deleteSleep(id: UUID) {
        guard let s = store.sleep(id: id) else { return }
        perform { try store.deleteSleep(s) }
    }

    /// «Vågnede» / «Sover igen» om natten
    func toggleWake() {
        perform {
            if store.openWake() != nil { try store.stopWake() } else { try store.startWake(by: role) }
        }
    }

    func deleteWake(id: UUID) {
        perform { try store.deleteWake(id: id) }
    }

    @discardableResult
    func feed(_ kind: FeedKind, amountMl: Double? = nil, milk: Milk = .breast, note: String = "", at time: Date?) -> Bool {
        perform { try store.addFeeding(kind, amountMl: amountMl, milk: milk, note: note, at: Self.resolve(time)) }
    }

    @discardableResult
    func pump(amountMl: Double, side: Side?, minutes: Double?, at time: Date?) -> Bool {
        perform { try store.addPumping(amountMl: amountMl, side: side, minutes: minutes, at: Self.resolve(time)) }
    }

    func deleteFeeding(id: UUID) {
        guard let f = store.feeding(id: id) else { return }
        perform { try store.delete(f) }
    }

    func answer(_ answer: Suggestions.Answer) {
        guard let id = snapshot.suggestion?.id else { return }
        perform { try store.answer(id, answer) }
    }

    // MARK: Vækst og udpumpning (ret/slet giver fejlteksten tilbage til arket)

    private func attempt(_ action: () throws -> Void) -> String? {
        defer { refresh() }
        do {
            try action()
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func saveGrowth(id: UUID?, date: Date, values: [WHO.Measure: Double?]) -> String? {
        attempt { try store.saveGrowth(id.flatMap(store.growth(id:)), date: date, values: values) }
    }

    func deleteGrowth(id: UUID) {
        _ = attempt { if let g = store.growth(id: id) { try store.delete(g) } }
    }

    func editPumping(id: UUID, time: Date, amountMl: Double, side: Side?, minutes: Double?) -> String? {
        attempt {
            if let p = store.pumping(id: id) {
                try store.editPumping(p, time: time, amountMl: amountMl, side: side, minutes: minutes)
            }
        }
    }

    func deletePumping(id: UUID) {
        _ = attempt { if let p = store.pumping(id: id) { try store.delete(p) } }
    }

    /// Vis skøn over næste tøjstørrelse på vækstsiden (pr. enhed, standard til)
    /// «Du kender dit barn bedst» er vist på denne enhed (én gang, før opsætningen)
    var welcomeSeen: Bool = FolkeShared.defaults.bool(forKey: "folke.welcomeSeen") {
        didSet { FolkeShared.defaults.set(welcomeSeen, forKey: "folke.welcomeSeen") }
    }

    var showNextSize: Bool = FolkeShared.defaults.object(forKey: "folke.showNextSize") as? Bool ?? true {
        didSet { FolkeShared.defaults.set(showNextSize, forKey: "folke.showNextSize") }
    }

    // MARK: Tavlen

    /// Seneste tavleversion, denne enhed har set (stjernerne ved månen blinker, når der er nyt)
    var boardSeen: Double = FolkeShared.defaults.double(forKey: "folke.boardSeen") {
        didSet { FolkeShared.defaults.set(boardSeen, forKey: "folke.boardSeen") }
    }

    var boardHasNews: Bool { snapshot.boardVersion > boardSeen }

    func openBoard() {
        page = .board
        boardSeen = snapshot.boardVersion
    }

    func addStroke(color: String, points: [SIMD2<Float>]) -> String? {
        attempt { try store.addStroke(color: color, points: points, by: role) }
    }

    func undoStroke() { _ = attempt { try store.undoStroke() } }
    func clearBoard() { _ = attempt { try store.clearBoard() } }

    // MARK: Indstillinger

    func setFeature(_ f: Feature, _ on: Bool) { perform { try store.setFeature(f, on) } }
    func setPumpRemind(_ hours: Double) { perform { try store.setPumpRemind(hours: hours) } }
    func setSex(_ sex: Sex) { perform { try store.setSex(sex) } }
    @discardableResult
    func rename(_ name: String) -> Bool { perform { try store.renameChild(name) } }

    func requestNotifications() async -> Bool {
        let ok = await notifier.requestPermission()
        refresh()
        return ok
    }

    func setNotificationMinutes(lead: Int? = nil, overdue: Int? = nil) {
        notifier.setMinutes(lead: lead, overdue: overdue)
        refresh()
    }

    func setNotification(_ kind: NotificationKind, _ on: Bool) {
        notifier.setEnabled(kind, on)
        refresh()
    }

    /// Første opstart: barnet (og evt. flere, fx tvillinger). Det første barn bliver valgt.
    func finishOnboarding(name: String, birthDate: Date?, sex: Sex, role: Role,
                          more: [(name: String, birthDate: Date, sex: Sex)] = []) {
        perform {
            if let child = store.child() {
                child.name = name
                try store.save()
            } else {
                let c = try store.createChild(name: name, birthDate: birthDate ?? .now, sex: sex)
                for m in more { try store.createChild(name: m.name, birthDate: m.birthDate, sex: m.sex) }
                store.currentChildID = c.id
                FolkeShared.childID = c.id
            }
            self.role = role
        }
    }

    // MARK: Flere børn

    /// Skift barn på denne enhed. Siden (Søvn, Mad …) bliver, hvor den er.
    func selectChild(_ id: UUID) {
        guard id != snapshot.childID else { return }
        store.currentChildID = id
        FolkeShared.childID = id
        napSelection = nil
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Tilføj et barn (navn, fødselsdato og køn). Det nye barn bliver valgt. Giver en fejltekst eller nil.
    func addChild(name: String, birthDate: Date, sex: Sex) -> String? {
        guard let clean = Format.cleanName(name) else { return "Skriv barnets navn (højst 40 tegn)" }
        guard birthDate <= .now else { return "Fødselsdatoen ligger i fremtiden" }
        return attempt {
            let c = try store.createChild(name: clean, birthDate: birthDate, sex: sex)
            FolkeShared.childID = c.id
        }
    }

    /// Slet det valgte barn med alle dets data (kun når der er flere børn).
    func deleteCurrentChild() {
        guard snapshot.children.count > 1, let c = store.child() else { return }
        perform {
            try store.deleteChild(c)
            FolkeShared.childID = store.child()?.id
            store.currentChildID = FolkeShared.childID
        }
    }

    // MARK: Skjult import fra Folke-serveren (PLAN.md afsnit 8)

    static func isOwnBuild() async -> Bool {
        #if DEBUG
        return true
        #else
        guard let t = try? await AppTransaction.shared.payloadValue else { return false }
        return t.environment != .production
        #endif
    }

    /// Importér en fil fra «Filer» (`GET /api/export` på serveren). Giver en tekst til brugeren.
    func importServer(_ url: URL) -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let r = try store.importServerExport(Data(contentsOf: url))
            refresh()
            return r.summary
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: Eksport som CSV

    /// De fire CSV-filer samlet i én zip-fil («Folke-eksport-<dato>.zip») til delingsarket.
    func exportCSV() -> URL? {
        let files = store.csvExport()
        let fm = FileManager.default
        let name = files.first.map { "Folke-eksport-" + $0.name.suffix(14).dropLast(4) } ?? "Folke-eksport"
        let root = fm.temporaryDirectory.appending(path: "eksport", directoryHint: .isDirectory)
        let dir = root.appending(path: name, directoryHint: .isDirectory)
        try? fm.removeItem(at: root)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for f in files { try f.data.write(to: dir.appending(path: f.name)) }
        } catch {
            return nil
        }
        // NSFileCoordinator zipper en mappe, når den læses «til upload»
        var zip: URL?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: dir, options: .forUploading, error: &err) { tmp in
            let dest = root.appending(path: name + ".zip")
            if (try? fm.copyItem(at: tmp, to: dest)) != nil { zip = dest }
        }
        return zip
    }
}
