import Foundation
import Testing
@testable import FolkeCore

/// Fælles testdata (tests/fixtures i roden af repoet), lavet af tests/fixtures/make_dayplan.py med folke.py som facit.
/// Python kører de samme filer (tests/test_fixtures.py), så reglerne ikke kan glide fra hinanden.
@Suite("Fælles testdata") struct FixtureTests {
    static let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appending(path: "tests/fixtures")

    static var files: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.appending(path: "dayplan").path)) ?? [])
            .filter { $0.hasSuffix(".json") }.sorted()
    }

    struct JSleep: Decodable { var id: Int; var start: String; var end: String; var nap: Bool }
    struct JItem: Decodable, Equatable { var kind: String; var start: String; var end: String?; var catnap: Bool }
    struct Expect: Decodable, Equatable {
        var items: [JItem]
        var wake: String?
        var missed_at: String?
        var short: Int?
        var bed_shift: Int
        var first_window: Int
        var after_catnap: Bool
    }
    struct Plan: Decodable { var description: String; var birth_date: String; var now: String; var running: String?
                             var sleeps: [JSleep]; var expect: Expect }

    static func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
    static func birth(_ s: String) -> Date {
        let p = s.split(separator: "-").map { Int($0)! }
        return cph.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))!
    }
    static func samples(_ s: [JSleep]) -> [SleepSample] {
        s.map { SleepSample(id: id($0.id), start: date($0.start), end: date($0.end), nap: $0.nap) }
    }
    static func hm(_ d: Date?) -> String? { d.map { Format.clock($0, calendar: cph) } }

    @Test func derErFixtures() {
        #expect(Self.files.count >= 8)
    }

    @Test(arguments: files) func dagsplan(_ file: String) throws {
        let d = try JSONDecoder().decode(Plan.self, from: Data(contentsOf: Self.dir.appending(path: "dayplan/\(file)")))
        let p = try #require(DayPlanner.plan(Self.samples(d.sleeps), birthDate: Self.birth(d.birth_date), now: Self.date(d.now),
                                              running: d.running.map(Self.date), calendar: cph))
        let got = Expect(items: p.items.map { JItem(kind: $0.kind.rawValue, start: Self.hm($0.start)!, end: Self.hm($0.end),
                                                     catnap: $0.catnap) },
                         wake: Self.hm(p.wake), missed_at: Self.hm(p.missedAt), short: p.short, bed_shift: p.bedShift,
                         first_window: p.firstWindow, after_catnap: p.afterCatnap)
        #expect(got == d.expect, "\(d.description)")
    }

    struct Measure: Decodable {
        struct E: Decodable { var n: Int; var median_abs: Double; var within_15: Double; var within_30: Double; var interval: [Int] }
        var birth_date: String
        var sleeps: [JSleep]
        var expect: E
    }

    @Test func maaling() throws {
        let d = try JSONDecoder().decode(Measure.self, from: Data(contentsOf: Self.dir.appending(path: "backtest.json")))
        let s = try #require(Backtest.summary(Backtest.run(Self.samples(d.sleeps), birthDate: Self.birth(d.birth_date),
                                                            calendar: cph)))
        #expect(s.n == d.expect.n && s.medianAbs == d.expect.median_abs)
        #expect(s.within15 == d.expect.within_15 && s.within30 == d.expect.within_30)
        #expect([s.interval.lo, s.interval.hi] == d.expect.interval)
    }

    // MARK: Urolig søvn (rough.py)

    static var roughFiles: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.appending(path: "rough").path)) ?? [])
            .filter { $0.hasSuffix(".json") }.sorted()
    }

    struct Rough: Decodable {
        struct W: Decodable { var start: String; var end: String? }
        struct E: Decodable { var key: String; var period: String?; var reasons: [String]; var title: String; var text: String }
        var description: String; var birth_date: String; var now: String; var name: String
        var sleeps: [JSleep]; var wakes: [W]; var expect: E?
    }

    @Test func derErFixturesOmUroligSoevn() {
        #expect(Self.roughFiles.count >= 7)
    }

    @Test(arguments: roughFiles) func uroligSoevn(_ file: String) throws {
        let d = try JSONDecoder().decode(Rough.self, from: Data(contentsOf: Self.dir.appending(path: "rough/\(file)")))
        let wakes = d.wakes.map { WakeItem(id: UUID(), start: Self.date($0.start), end: $0.end.map(Self.date)) }
        let r = RoughPatch.check(sleeps: Self.samples(d.sleeps), wakes: wakes, birthDate: Self.birth(d.birth_date),
                                 now: Self.date(d.now), name: d.name, calendar: cph)
        let want = d.expect.map { RoughSleep(key: $0.key, period: $0.period, reasons: $0.reasons, title: $0.title, text: $0.text) }
        #expect(r == want, "\(d.description)")
    }

    // MARK: Notifikationernes tekster (messages.py)

    struct MessageFile: Decodable {
        struct P: Decodable { var kind: String; var when: String; var name: String; var t: String; var h: String; var expect: String }
        var lists: [String: [String]]
        var picks: [P]
    }

    @Test func beskeder() throws {
        let d = try JSONDecoder().decode(MessageFile.self, from: Data(contentsOf: Self.dir.appending(path: "messages.json")))
        #expect(d.lists.count == Messages.Kind.allCases.count)
        for k in Messages.Kind.allCases {
            #expect(d.lists[k.rawValue] == Messages.list(k), "\(k.rawValue)")
        }
        for p in d.picks {
            let k = try #require(Messages.Kind(rawValue: p.kind))
            #expect(Messages.pick(k, when: Self.date(p.when), name: p.name, t: p.t, h: p.h) == p.expect)
        }
    }

    // MARK: Glemt nat (folke.missing_night)

    static var missingFiles: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.appending(path: "missing").path)) ?? [])
            .filter { $0.hasSuffix(".json") }.sorted()
    }

    struct Missing: Decodable {
        struct E: Decodable { var start: String; var end: String }
        var description: String; var now: String; var running: String?; var sleeps: [JSleep]; var expect: E?
    }

    @Test func derErFixturesOmGlemtNat() {
        #expect(Self.missingFiles.count >= 9)
    }

    @Test(arguments: missingFiles) func glemtNat(_ file: String) throws {
        let d = try JSONDecoder().decode(Missing.self, from: Data(contentsOf: Self.dir.appending(path: "missing/\(file)")))
        let m = MissingNight.check(Self.samples(d.sleeps), now: Self.date(d.now), running: d.running.map(Self.date), calendar: cph)
        #expect(m?.start == d.expect.map { Self.date($0.start) }, "\(d.description)")
        #expect(m?.end == d.expect.map { Self.date($0.end) }, "\(d.description)")
    }

    // MARK: Søvn i tal (stats.py)

    static var statsFiles: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.appending(path: "stats").path)) ?? [])
            .filter { $0.hasSuffix(".json") }.sorted()
    }

    struct StatsFile: Decodable {
        struct W: Decodable { var start: String; var end: String? }
        struct D: Decodable {
            var date: String; var naps: Int?; var day_min: Int?; var night_min: Int?; var total_min: Int?
            var bed: Int?; var wake: Int?; var wakes: Int?; var nap_len: Int?
        }
        struct S: Decodable {
            var days: Int; var total_min: Int?; var night_min: Int?; var day_min: Int?; var nap_len: Int?
            var bed: Int?; var wake: Int?; var naps: Double?; var wakes: Double?
        }
        struct E: Decodable { var days: [D]; var week: S; var prev: S; var text: String? }
        var description: String; var now: String; var name: String; var sleeps: [JSleep]; var wakes: [W]; var expect: E
    }

    @Test func derErFixturesOmSoevnITal() {
        #expect(Self.statsFiles.count >= 5)
    }

    @Test(arguments: statsFiles) func soevnITal(_ file: String) throws {
        let d = try JSONDecoder().decode(StatsFile.self, from: Data(contentsOf: Self.dir.appending(path: "stats/\(file)")))
        let wakes = d.wakes.map { WakeItem(id: UUID(), start: Self.date($0.start), end: $0.end.map(Self.date)) }
        let r = SleepStats.make(sleeps: Self.samples(d.sleeps), wakes: wakes, now: Self.date(d.now), name: d.name, calendar: cph)
        let f = DateFormatter()
        f.calendar = cph
        f.timeZone = cph.timeZone
        f.dateFormat = "yyyy-MM-dd"
        #expect(r.days.map { f.string(from: $0.date) } == d.expect.days.map(\.date), "\(d.description)")
        for (got, want) in zip(r.days, d.expect.days) {
            let g = got.registered
                ? StatsFile.D(date: want.date, naps: got.naps, day_min: got.dayMin, night_min: got.nightMin, total_min: got.totalMin,
                              bed: got.bed, wake: got.wake, wakes: got.wakes, nap_len: got.napLen)
                : StatsFile.D(date: want.date)
            #expect([g.naps, g.day_min, g.night_min, g.total_min, g.bed, g.wake, g.wakes, g.nap_len]
                    == [want.naps, want.day_min, want.night_min, want.total_min, want.bed, want.wake, want.wakes, want.nap_len],
                    "\(d.description) \(want.date)")
        }
        for (got, want) in [(r.week, d.expect.week), (r.prev, d.expect.prev)] {
            #expect(got.days == want.days && got.totalMin == want.total_min && got.nightMin == want.night_min
                    && got.dayMin == want.day_min && got.napLen == want.nap_len && got.bed == want.bed && got.wake == want.wake
                    && got.naps == want.naps && got.wakes == want.wakes, "\(d.description)")
        }
        #expect(r.text == d.expect.text, "\(d.description)")
    }
}
