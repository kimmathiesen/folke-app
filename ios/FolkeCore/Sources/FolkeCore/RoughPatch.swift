import Foundation

/// Urolig søvn: en blid besked, når søvnen er tydeligt dårligere end normalt (port af `rough.py`, samme testdata i
/// tests/fixtures/rough). De seneste 4 hele dage holdes op mod de 14 dage før. Er mindst to ting tydeligt dårligere,
/// kommer en besked, og ligger barnet i en kendt periode (fx 4-måneders søvnregressionen), forklarer den perioden.
/// Tigerspring er bevidst ikke med.
public struct RoughSleep: Equatable, Sendable {
    /// Én pr. periode («p-4m») eller pr. uge uden periode («u-2026-43»): «Tak» skjuler beskeden for den nøgle
    public var key: String
    public var period: String?
    public var reasons: [String]
    public var title: String
    public var text: String
}

public enum RoughPatch {
    public static let recentDays = 4
    public static let baseDays = 14
    static let minRecent = 3
    static let minBase = 7
    static let minFlags = 2

    /// (id, fra uge, til uge (ikke medregnet), forklaring). Ugerne regnes fra fødslen.
    static let periods: [(id: String, from: Int, to: Int, text: String)] = [
        ("4m", 14, 23, "Omkring 4 måneder ændrer søvnen sig hos mange børn: den bliver lettere og mere som voksnes. "
            + "Det kaldes ofte 4-måneders søvnregressionen og kan give flere opvågninger og kortere lure i en periode."),
        ("8m", 34, 47, "Omkring 8–10 måneder øver mange børn sig i at kravle og rejse sig, og de lægger mere mærke til, "
            + "når du går. Det kan give uroligere søvn i en periode."),
        ("12m", 50, 57, "Omkring 1 år går mange børn fra to lure mod én, og nye ting som at gå kan forstyrre søvnen "
            + "i en periode."),
        ("18m", 76, 85, "Omkring 1½ år vil mange børn gerne bestemme mere selv, og hjørnetænderne kommer ofte. "
            + "Det kan give mere uro ved puttetid og om natten."),
        ("24m", 100, 109, "Omkring 2 år tester mange børn grænser ved puttetid, og fantasien vokser, så nogle får "
            + "sværere ved at falde til ro."),
    ]

    /// I den rækkefølge, de nævnes
    static let reasonTexts: [(String, String)] = [
        ("wakes", "flere opvågninger om natten"), ("night", "kortere nætter"), ("naps", "kortere lure"),
        ("short", "flere korte lure"), ("day", "mindre søvn om dagen"),
    ]

    static let title = "Søvnen er lidt urolig lige nu"
    static let other = "Det sker for alle børn en gang imellem, fx ved tænder, forkølelse eller nye ting, de øver sig på. "
        + "Det går som regel over igen."

    static func period(birthDate: Date, today: Date, calendar: Calendar) -> (id: String, from: Int, to: Int, text: String)? {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: birthDate), to: today).day ?? 0
        let weeks = Int((Double(days) / 7).rounded(.down))
        return periods.first { $0.from <= weeks && weeks < $0.to }
    }

    private struct Day {
        var naps: [Double]
        var night: Double?
        var wakes: Int
    }

    /// Tal pr. dag (kun dage med registreringer). Natten hører til dagen, den starter.
    private static func days(_ sleeps: [SleepSample], _ wakes: [WakeItem], first: Date, count: Int,
                             calendar: Calendar) -> [Day] {
        (0..<count).compactMap { i in
            guard let d = calendar.date(byAdding: .day, value: i, to: first) else { return nil }
            let naps = sleeps.filter { $0.nap && calendar.isDate($0.start, inSameDayAs: d) }
            let nights = sleeps.filter { !$0.nap && calendar.isDate($0.start, inSameDayAs: d) }
            if naps.isEmpty && nights.isEmpty { return nil }
            var count = 0, awake = 0.0
            for n in nights {
                for w in wakes where n.start <= w.start && w.start <= n.end {
                    count += 1
                    awake += min(w.end ?? n.end, n.end).timeIntervalSince(w.start) / 60
                }
            }
            return Day(naps: naps.map { $0.end.timeIntervalSince($0.start) / 60 },
                       night: nights.isEmpty ? nil
                           : nights.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) / 60 } - awake,
                       wakes: count)
        }
    }

    private static func mean(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }

    private struct Stats {
        var day, napLen, short, night, wakes: Double?
    }

    private static func stats(_ days: [Day]) -> Stats {
        let withNight = days.filter { $0.night != nil }
        return Stats(day: mean(days.map { $0.naps.reduce(0, +) }),
                     napLen: mean(days.flatMap(\.naps)),
                     short: mean(days.map { Double($0.naps.filter { $0 < DayPlanner.shortNap }.count) }),
                     night: mean(withNight.compactMap(\.night)),
                     wakes: mean(withNight.map { Double($0.wakes) }))
    }

    /// En besked om urolig søvn, eller nil.
    public static func check(sleeps: [SleepSample], wakes: [WakeItem], birthDate: Date, now: Date, name: String,
                             calendar: Calendar = .current) -> RoughSleep? {
        let today = calendar.startOfDay(for: now)
        guard let recentFirst = calendar.date(byAdding: .day, value: -recentDays, to: today),
              let baseFirst = calendar.date(byAdding: .day, value: -(recentDays + baseDays), to: today) else { return nil }
        let recent = days(sleeps, wakes, first: recentFirst, count: recentDays, calendar: calendar)
        let base = days(sleeps, wakes, first: baseFirst, count: baseDays, calendar: calendar)
        guard recent.count >= minRecent, base.count >= minBase else { return nil }
        let r = stats(recent), b = stats(base)
        var flags = Set<String>()
        // Opvågninger tæller kun, hvis de også blev registreret før (ellers ligner det en forværring, at man er begyndt)
        if let bw = b.wakes, let rw = r.wakes, base.contains(where: { $0.wakes > 0 }), rw >= bw + 1, rw >= 1.5 * bw {
            flags.insert("wakes")
        }
        if let bn = b.night, bn > 0, let rn = r.night, rn <= 0.85 * bn { flags.insert("night") }
        if let bl = b.napLen, bl > 0, let rl = r.napLen, rl <= 0.75 * bl { flags.insert("naps") }
        if let bs = b.short, let rs = r.short, rs >= bs + 1 { flags.insert("short") }
        if let bd = b.day, bd > 0, let rd = r.day, rd <= 0.8 * bd { flags.insert("day") }
        guard flags.count >= minFlags else { return nil }

        let picked = reasonTexts.filter { flags.contains($0.0) }
        let words = picked.map(\.1)
        let why = words.count == 1 ? words[0] : words.dropLast().joined(separator: ", ") + " og " + words.last!
        let p = period(birthDate: birthDate, today: today, calendar: calendar)
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let wk = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        let who = name.isEmpty ? "Jeres barn" : name
        return RoughSleep(key: p.map { "p-\($0.id)" }
                              ?? String(format: "u-%d-%02d", wk.yearForWeekOfYear ?? 0, wk.weekOfYear ?? 0),
                          period: p?.id, reasons: picked.map(\.0), title: title,
                          text: "\(who) har sovet lidt dårligere de seneste dage (\(why)). \(p?.text ?? other) Husk, at du gør det godt.")
    }
}

public extension FolkeStore {
    /// Besked om urolig søvn for det valgte barn (de seneste 4 hele dage mod de 14 før)
    func roughSleep(now: Date = .now) -> RoughSleep? {
        guard let c = child(), let birth = c.birthDate else { return nil }
        let since = now.addingTimeInterval(-Double(RoughPatch.recentDays + RoughPatch.baseDays + 2) * 86400)
        return RoughPatch.check(sleeps: sleeps(since: since).compactMap(\.sample), wakes: wakes(from: since),
                                birthDate: birth, now: now, name: c.name ?? "", calendar: calendar)
    }
}
