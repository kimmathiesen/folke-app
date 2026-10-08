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
}
