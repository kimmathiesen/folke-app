#if DEBUG
import FolkeCore
import Foundation

extension FolkeStore {
    /// Barn på `months` måneder. Søvn som historikken i tests/test_predict.py: nat 19:30-6:30 og lure 8:30-9:30, 12:00-13:30 og 16:30-17:00.
    func seedDemo(months: Int = 4, now: Date = .now) throws {
        let cal = calendar
        let today = cal.startOfDay(for: now)
        let child = try createChild(name: "Folke", birthDate: cal.date(byAdding: .month, value: -months, to: today)!)
        func at(_ d: Date, _ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: d)! }
        for i in (0..<10).reversed() {
            let d = cal.date(byAdding: .day, value: -i, to: today)!
            let yesterday = cal.date(byAdding: .day, value: -1, to: d)!
            let spans = [(at(yesterday, 19, 30), at(d, 6, 30), false), (at(d, 8, 30), at(d, 9, 30), true),
                         (at(d, 12, 0), at(d, 13, 30), true), (at(d, 16, 30), at(d, 17, 0), true)]
            for (start, end, nap) in spans where end <= now {
                let s = Sleep(context: context)
                s.id = UUID()
                s.start = start
                s.end = end
                s.nap = nap
                s.createdBy = "mor"
                s.child = child
            }
        }
        try save()
        for (h, m, kind, ml) in [(7, 0, FeedKind.left, 0.0), (10, 30, .both, 0), (15, 10, .bottle, 120)]
        where at(today, h, m) <= now {
            try addFeeding(kind, amountMl: ml, at: at(today, h, m), now: now)
        }
        for (h, m, ml, side) in [(9, 15, 140.0, Side.both), (13, 40, 120, .left)] where at(today, h, m) <= now {
            try addPumping(amountMl: ml, side: side, minutes: 15, at: at(today, h, m), now: now)
        }
        // 13 hele dage med 2-4 udpumpninger
        for i in 1...13 {
            let d = cal.date(byAdding: .day, value: -i, to: today)!
            for (j, h) in [7, 11, 15, 19].prefix(2 + i % 3).enumerated() {
                try addPumping(amountMl: Double(90 + (i * 37 + j * 23) % 70), side: .both, minutes: 15, at: at(d, h, 0), now: now)
            }
        }
        // Vækst ved fødslen og hver måned
        for (mo, w, l, hc) in [(0, 3.5, 50.5, 35.0), (1, 4.6, 54.5, 37.4), (2, 5.7, 58.2, 39.1), (3, 6.4, 61.0, 40.5),
                               (5, 7.6, 65.5, 42.4), (6, 8.0, 67.4, 43.2)] {
            let d = cal.date(byAdding: .month, value: mo - months, to: today)!
            if d <= now { try saveGrowth(date: d, values: [.weight: w, .length: l, .head: hc], now: now) }
        }
    }
}
#endif

