import Foundation

/// Glemt nat (port af `folke.missing_night`, samme testdata i tests/fixtures/missing). Mangler natten fra i går
/// (fx glemt at trykke), foreslås hans typiske sengetid og opvågning, så den kan tilføjes med ét tryk.
public enum MissingNight {
    /// Kun efter kl. 5, kun hvis i går er registreret, og kun hvis ingen nat ligger mellem i går kl. 15 og i dag kl. 9
    /// (og ingen søvn har kørt siden før kl. 5). Starten er hans typiske sengetid (dog ikke før sidste søvn i går),
    /// slutningen hans typiske opvågning (dog ikke efter første søvn i dag eller nu). Afrundet til 5 min.
    public static func check(_ sleeps: [SleepSample], now: Date, running: Date? = nil,
                             calendar: Calendar = .current) -> (start: Date, end: Date)? {
        let today = calendar.startOfDay(for: now)
        guard let yday = calendar.date(byAdding: .day, value: -1, to: today) else { return nil }
        func at(_ d: Date, _ m: Int) -> Date { calendar.date(byAdding: .minute, value: m, to: d)! }
        guard calendar.component(.hour, from: now) >= 5,
              sleeps.contains(where: { calendar.isDate($0.start, inSameDayAs: yday) }) else { return nil }
        let lo = at(yday, 15 * 60), hi = at(today, 9 * 60)
        if sleeps.contains(where: { !$0.nap && $0.end > lo && $0.start < hi }) { return nil }
        if let running, running < at(today, 5 * 60) { return nil }
        let from = calendar.date(byAdding: .day, value: -15, to: today)!
        let nights = sleeps.filter { !$0.nap && calendar.startOfDay(for: $0.start) >= from }

        func minutes(_ d: Date) -> Int {
            let c = calendar.dateComponents([.hour, .minute], from: d)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        func typical(_ xs: [Int], _ fallback: Int) -> Int {
            guard !xs.isEmpty else { return fallback }
            return Int((Predictor.median(xs.map(Double.init)) / 5).rounded(.toNearestOrEven)) * 5
        }
        let bed = typical(nights.map { minutes($0.start) + (calendar.component(.hour, from: $0.start) < 12 ? 1440 : 0) },
                          19 * 60 + 30)
        let wake = typical(nights.map { minutes($0.end) }, 6 * 60 + 30)
        var start = at(yday, bed)
        if let last = sleeps.filter({ $0.start < today }).map(\.end).max() { start = max(start, last) }
        let firsts = sleeps.filter { calendar.isDate($0.start, inSameDayAs: today) }.map(\.start) + (running.map { [$0] } ?? [])
        let end = ([at(today, wake), now] + firsts).min()!
        return end > start ? (start, end) : nil
    }
}

public extension FolkeStore {
    /// Forslag til den glemte nat for det valgte barn, eller nil
    func missingNight(now: Date = .now) -> (start: Date, end: Date)? {
        let samples = sleeps(since: now.addingTimeInterval(-17 * 86400)).compactMap(\.sample)
        return MissingNight.check(samples, now: now, running: runningSleep()?.start, calendar: calendar)
    }
}
