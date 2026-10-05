#if DEBUG
import FolkeCore
import Foundation

extension FolkeStore {
    /// Som historikken i tests/test_predict.py: nat 19:30-6:30 og lure 8:30-9:30, 12:00-13:30 og 16:30-17:00.
    func seedDemo(now: Date = .now) throws {
        let cal = calendar
        let today = cal.startOfDay(for: now)
        let child = try createChild(name: "Folke", birthDate: cal.date(byAdding: .month, value: -4, to: today)!)
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
    }
}
#endif
