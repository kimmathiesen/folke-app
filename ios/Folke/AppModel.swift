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
    private(set) var snapshot = Snapshot()
    var error: String?
    /// Lur/Nat-valg, mens søvnen kører (nil = gæt ud fra klokkeslættet)
    var napSelection: Bool?
    /// Siden, der vises (som hash-ruterne i webappen)
    var page: Page = .home

    enum Page { case home, settings, growth, pump, board }

    var role: Role? {
        didSet { FolkeShared.role = role }
    }

    /// Import fra Folke-serveren vises kun i egne builds (Xcode, TestFlight), aldrig i App Store-udgaven.
    private(set) var importAvailable = false

    init(store: FolkeStore) {
        self.store = store
        role = FolkeShared.role
        refresh()
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
                    try store.seedDemo(months: months > 0 ? months : 4)
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
            s.running = .init(id: id, start: start, end: now, nap: r.nap)
        } else {
            napSelection = nil
        }
        s.awakeSince = store.awakeSince(now: now)
        s.prediction = store.prediction(now: now)
        s.plan = store.dayPlan(now: now)
        s.today = store.todaySleeps(now: now).compactMap { x in
            guard let id = x.id, let start = x.start, let end = x.end else { return nil }
            return .init(id: id, start: start, end: end, nap: x.nap)
        }
        if let set = store.settings() {
            s.featureBreast = set.featureBreast
            s.featureSolids = set.featureSolids
            s.featurePump = set.featurePump
            s.pumpRemindHours = set.pumpRemindHours
        }
        s.sex = child?.sex.flatMap(Sex.init(rawValue:)) ?? .boy
        if let f = store.lastFeeding(now: now), let t = f.time, let k = f.kind.flatMap(FeedKind.init(rawValue:)) {
            s.lastFeed = (k, f.amountMl, t)
        }
        s.pump = store.pumpSummary(now: now)
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
        syncExtensions(s)
        notifier.reschedule(.init(now: now, prediction: s.prediction, sleeping: s.running != nil, childName: s.childName,
                                  enabled: [], pumpFeature: s.featurePump, pumpRemindHours: s.pumpRemindHours,
                                  lastPump: store.lastPumping(now: now)))
    }

    private var widgetKey = ""

    /// Live Activity og widgets følger appen. Widgets genindlæses kun, når noget, de viser, har ændret sig.
    private func syncExtensions(_ s: Snapshot) {
        let running = s.running.map { ($0.start, $0.nap) }, name = s.childName, wake = s.plan?.wake
        Task { await SleepLiveActivity.sync(running: running, name: name, expectedWake: wake) }
        let key = [s.running?.start.description, s.awakeSince?.description,
                   s.plan?.items.map { $0.start.description }.joined(), s.childName].map { $0 ?? "-" }.joined(separator: "|")
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
        perform { try store.delete(s) }
    }

    @discardableResult
    func feed(_ kind: FeedKind, amountMl: Double? = nil, milk: Milk = .breast, note: String = "", at time: Date?) -> Bool {
        perform { try store.addFeeding(kind, amountMl: amountMl, milk: milk, note: note, at: Self.resolve(time)) }
    }

    @discardableResult
    func pump(amountMl: Double, side: Side?, minutes: Double?, at time: Date?) -> Bool {
        perform { try store.addPumping(amountMl: amountMl, side: side, minutes: minutes, at: Self.resolve(time)) }
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

    func setNotification(_ kind: NotificationKind, _ on: Bool) {
        notifier.setEnabled(kind, on)
        refresh()
    }

    func finishOnboarding(name: String, birthDate: Date?, sex: Sex, role: Role) {
        perform {
            if let child = store.child() {
                child.name = name
                try store.save()
            } else {
                try store.createChild(name: name, birthDate: birthDate ?? .now, sex: sex)
            }
            self.role = role
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
}
