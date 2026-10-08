import Foundation

public extension Predictor {
    /// Gratisudgaven af forudsigelsen: den oprindelige `predict()` fra den selfhostede server (før dagsplanen, 6/10 2026).
    /// Kun næste lur eller sengetid ud fra medianen af hans vågenvinduer for netop den plads på dagen (de seneste 7),
    /// ellers alle vinduer (mindst 5) eller alderen. Ingen genberegning, korte lure, aftenlur eller rykket sengetid:
    /// det er med i Folke Plus (`DayPlanner`).
    static func basic(_ sleeps: [SleepSample], birthDate: Date, now: Date, calendar: Calendar = .current) -> Prediction? {
        let sleeps = sleeps.sorted { $0.start < $1.start }
        guard let last = sleeps.last else { return nil }

        // Vågenvinduer pr. position på dagen (0 = morgen, 1 = efter 1. lur ...)
        var windows: [Int: [Double]] = [:]
        var allGaps: [Double] = []
        var pos = 0
        for (prev, next) in zip(sleeps, sleeps.dropFirst()) {
            pos = prev.nap ? pos + 1 : 0
            let gap = next.start.timeIntervalSince(prev.end) / 60
            if gap > 20 && gap < 480 {
                windows[pos, default: []].append(gap)
                allGaps.append(gap)
            }
        }
        // Position for den næste søvn
        pos = 0
        for s in sleeps { pos = s.nap ? pos + 1 : 0 }

        let ageDays = calendar.dateComponents([.day], from: calendar.startOfDay(for: birthDate),
                                              to: calendar.startOfDay(for: now)).day ?? 0
        let samples = Array((windows[pos] ?? []).suffix(7))
        let window: Double, source: Prediction.Source
        if samples.count >= 3 {
            (window, source) = (median(samples), .position(pos))
        } else if allGaps.count >= 5 {
            (window, source) = (median(Array(allGaps.suffix(15))), .allWindows)
        } else {
            (window, source) = (Double(defaultWindow(ageDays: ageDays)), .ageDefault)
        }
        let nextStart = last.end.addingTimeInterval(window * 60)

        // Typisk sengetid = median af aftensøvne (kl. 17-24)
        let evenings = sleeps.filter { !$0.nap && calendar.component(.hour, from: $0.start) >= 17 }.map {
            Double(calendar.component(.hour, from: $0.start) * 60 + calendar.component(.minute, from: $0.start))
        }
        let bedMin = evenings.count >= 3 ? Int(median(evenings)) : defaultBedtimeMin
        let bed = calendar.date(bySettingHour: bedMin / 60, minute: bedMin % 60, second: 0, of: nextStart)!

        // Er sengetiden allerede gået (sent på aftenen), er det sengetid, så snart vinduet er gået
        let isBed = nextStart >= bed.addingTimeInterval(-60 * 60)
        return Prediction(kind: isBed ? .bedtime : .nap, time: isBed ? max(bed, nextStart) : nextStart,
                          windowMin: Int(window.rounded(.toNearestOrEven)), source: source, lastID: last.id, pos: pos,
                          bedBasis: evenings.count >= 3 ? .own : .default)
    }
}
