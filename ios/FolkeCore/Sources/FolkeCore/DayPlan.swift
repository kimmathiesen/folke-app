import Foundation

/// Et punkt i dagsplanen: en lur (start og slut) eller sengetid (kun start).
public struct PlanItem: Equatable, Sendable {
    public var kind: Prediction.Kind
    public var start: Date
    public var end: Date?
    /// Aftenlur, planlagt fordi der ikke var plads til en hel lur
    public var catnap = false

    public init(kind: Prediction.Kind, start: Date, end: Date? = nil, catnap: Bool = false) {
        self.kind = kind
        self.start = start
        self.end = end
        self.catnap = catnap
    }
}

/// Resten af dagen (port af `plan_day` i folke.py, ios/PLAN.md afsnit 3).
public struct DayPlan: Equatable, Sendable {
    public var items: [PlanItem]
    /// Forventet opvågning, hvis en lur er i gang
    public var wake: Date?
    /// Oprindeligt planlagt tidspunkt, hvis luren blev sprunget over
    public var missedAt: Date?
    /// Længden af en kort lur lige før (min)
    public var short: Int?
    /// Minutter sengetiden er rykket frem
    public var bedShift: Int
    public var firstWindow: Int
    public var source: Prediction.Source
    public var pos: Int
    public var bedBasis: Prediction.BedBasis
    public var naps: Int
    /// Han plejer at tage en aftenlur
    public var catnap: Bool
    public var lastID: UUID
}

/// Dagsplan med genberegning. Konstanterne og reglerne er de samme som i folke.py.
public enum DayPlanner {
    static let shortNap = 30.0
    static let shortFactor = 0.75
    static let outlier = (0.6, 1.6)
    static let maxBedShift = 60.0
    static let defaultNapLen = 60.0
    static let catnapFrom = 17 * 60
    static let defaultCatnapLen = 45.0
    static let nightMin = 120.0
    static let deficit = 30.0
    static let learnDays = 3
    static let maxDayHours = 36.0
    static let overdueMin = 15.0

    struct S {
        var id: UUID
        var start: Date
        var end: Date
        var nap: Bool
    }

    static func mins(_ a: Date, _ b: Date) -> Double { b.timeIntervalSince(a) / 60 }

    static func isShort(_ s: S) -> Bool { s.nap && mins(s.start, s.end) < shortNap }

    /// Typisk antal lure om dagen efter alder, til der er data nok.
    public static func defaultNaps(ageDays: Int) -> Int {
        let months = Double(ageDays) / 30.4
        for (limit, n) in [(4.0, 4), (7, 3), (15, 2)] where months < limit {
            return n
        }
        return 1
    }

    /// De sidste n prøver, uden afvigere (hvis der er nok til at se, hvad der er normalt).
    static func robust(_ samples: [Double], _ n: Int) -> [Double] {
        var s = samples
        if s.count >= 4 {
            let m = Predictor.median(s)
            s = s.filter { $0 >= outlier.0 * m && $0 <= outlier.1 * m }
        }
        return Array(s.suffix(n))
    }

    /// Gæt på lur eller nat, når en søvn stoppes uden at brugeren har valgt: som ved start, men en «nat» under 2 timer,
    /// der slutter samme dag, er en aftenlur.
    public static func napAtStop(start: Date, end: Date, calendar: Calendar = .current) -> Bool {
        if Predictor.napGuess(start, calendar: calendar) { return true }
        return mins(start, end) < nightMin && calendar.isDate(end, inSameDayAs: start)
    }

    /// Tidligere registreringer: en kort «nat», der sluttede samme aften, læses som lur.
    static func normalize(_ s: S, _ cal: Calendar) -> S {
        var s = s
        if !s.nap && mins(s.start, s.end) < nightMin && cal.isDate(s.end, inSameDayAs: s.start) {
            s.nap = true
        }
        return s
    }

    /// Hans egne tal, lært af historikken (`_Model`).
    struct Model {
        let ageDays: Int
        let cal: Calendar
        var windows: [Int: [Double]] = [:]
        var allGaps: [Double] = []
        var lengths: [Int: [Double]] = [:]
        var allLengths: [Double] = []
        var napsPerDay: [Int] = []
        var evenings: [Double] = []
        /// Hele dage: (dagsøvn, natten starter, sidste søvns slut, aftenlur)
        var days: [(slept: Double, night: Date, lastEnd: Date, catnap: S?)] = []

        func clock(_ d: Date) -> Int {
            let c = cal.dateComponents([.hour, .minute], from: d)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }

        init(_ sleeps: [S], ageDays: Int, calendar: Calendar) {
            self.ageDays = ageDays
            cal = calendar
            var pos = 0, k = 0
            var night: S?
            var day: [S] = []
            for (i, s) in sleeps.enumerated() {
                if !s.nap {
                    if let n = night, mins(n.end, s.start) < maxDayHours * 60 {
                        napsPerDay.append(k)
                        let lastNap = day.last { !isShort($0) }
                        let catnap = lastNap.flatMap { clock($0.start) >= catnapFrom ? $0 : nil }
                        days.append((day.reduce(0) { $0 + mins($1.start, $1.end) }, s.start, day.last?.end ?? n.end, catnap))
                    }
                    night = s
                    pos = 0
                    k = 0
                    day = []
                    if cal.component(.hour, from: s.start) >= 17 {
                        evenings.append(Double(clock(s.start)))
                    }
                } else {
                    day.append(s)
                }
                if s.nap && !isShort(s) {
                    k += 1
                    let d = mins(s.start, s.end)
                    lengths[k, default: []].append(d)
                    allLengths.append(d)
                }
                if i + 1 < sleeps.count {
                    let next = sleeps[i + 1]
                    if s.nap && !isShort(s) { pos += 1 }
                    if isShort(s) || isShort(next) { continue }
                    let gap = mins(s.end, next.start)
                    if gap > 20 && gap < 480 {
                        windows[pos, default: []].append(gap)
                        allGaps.append(gap)
                    }
                }
            }
        }

        func window(_ pos: Int) -> (Double, Prediction.Source) {
            let own = robust(windows[pos] ?? [], 7)
            if own.count >= 3 { return (Predictor.median(own), .position(pos)) }
            let every = robust(allGaps, 15)
            if every.count >= 5 { return (Predictor.median(every), .allWindows) }
            return (Double(Predictor.defaultWindow(ageDays: ageDays)), .ageDefault)
        }

        func napLength(_ k: Int) -> Double {
            let own = robust(lengths[k] ?? [], 7)
            if own.count >= 3 { return Predictor.median(own) }
            let every = robust(allLengths, 15)
            return every.count >= 3 ? Predictor.median(every) : defaultNapLen
        }

        func naps() -> Int {
            let d = napsPerDay.suffix(7).map(Double.init)
            return d.count >= 3 ? Int(Predictor.median(d).rounded(.toNearestOrEven)) : defaultNaps(ageDays: ageDays)
        }

        func bedMin() -> Int {
            evenings.count >= 3 ? Int(Predictor.median(evenings)) : Predictor.defaultBedtimeMin
        }

        func catnapHabit() -> Bool {
            let recent = days.suffix(7)
            let n = recent.filter { $0.catnap != nil }.count
            return n >= 3 && 2 * n >= recent.count
        }

        func catnapLength() -> Double {
            let own = robust(days.compactMap { $0.catnap.map { mins($0.start, $0.end) } }, 7)
            return own.isEmpty ? defaultCatnapLen : Predictor.median(own)
        }

        func eveningGap() -> Double? {
            let own = robust(days.filter { $0.catnap != nil }.map { mins($0.lastEnd, $0.night) }, 7)
            return own.count >= 3 ? Predictor.median(own) : nil
        }

        func normalDaySleep() -> Double {
            let d = days.suffix(7).map(\.slept)
            if d.count >= 3 { return Predictor.median(Array(d)) }
            return (1...max(1, naps())).reduce(0) { $0 + napLength($1) }
        }

        func learnedShift() -> Int {
            guard days.count >= 3 else { return 0 }
            let normal = Predictor.median(days.map(\.slept)), bed = Double(bedMin())
            let earlier = days.filter { $0.slept <= normal - deficit && cal.component(.hour, from: $0.night) >= 17 }
                .map { bed - Double(clock($0.night)) }
            guard earlier.count >= learnDays else { return 0 }
            let shift = Predictor.median(earlier)
            return shift >= 15 ? Int(min(maxBedShift, shift).rounded(.toNearestOrEven)) : 0
        }
    }

    /// Plan for resten af dagen. `running`: starttidspunkt for en lur, der er i gang.
    /// `replan`: er han stadig vågen 15 min efter planlagt lur, er næste lur «nu» (kun til skærmen).
    public static func plan(_ samples: [SleepSample], birthDate: Date, now: Date, running: Date? = nil,
                            replan: Bool = true, calendar cal: Calendar = .current) -> DayPlan? {
        let sleeps = samples.map { normalize(S(id: $0.id, start: $0.start, end: $0.end, nap: $0.nap), cal) }
            .sorted { $0.start < $1.start }
        guard let last = sleeps.last else { return nil }
        let ageDays = cal.dateComponents([.day], from: cal.startOfDay(for: birthDate), to: cal.startOfDay(for: now)).day ?? 0
        let m = Model(sleeps, ageDays: ageDays, calendar: cal)
        let add = { (d: Date, minutes: Double) in d.addingTimeInterval(minutes * 60) }

        // Dagen indtil nu: lure siden sidste nat
        var today: [S] = []
        for s in sleeps.reversed() {
            if !s.nap { break }
            today.insert(s, at: 0)
        }
        var k = today.filter { !isShort($0) }.count
        var slept = today.reduce(0) { $0 + mins($1.start, $1.end) }
        var pos = k

        var (win, source) = m.window(pos)
        let short = isShort(last) ? Int(mins(last.start, last.end).rounded(.toNearestOrEven)) : nil
        if short != nil {
            win *= shortFactor
        } else if last.nap, m.clock(last.start) >= catnapFrom, m.catnapHabit(), let gap = m.eveningGap() {
            win = gap // efter aftenluren: hans typiske tid vågen før natten
        }
        var wake = last.end
        var t = add(last.end, win)
        var firstWin = win, firstPos = pos
        var wakeAt: Date?

        if let running {
            let length = m.napLength(k + 1)
            wake = max(add(running, length), now)
            wakeAt = wake
            k += 1
            pos += 1
            slept += mins(running, wake)
            (win, source) = m.window(pos)
            t = add(wake, win)
            firstWin = win
            firstPos = pos
        }

        let bedMin = m.bedMin()
        func bedOn(_ x: Date) -> Date {
            cal.date(bySettingHour: bedMin / 60, minute: bedMin % 60, second: 0, of: x) ?? x
        }

        var missedAt: Date?
        if replan, running == nil, now > add(t, overdueMin), t < add(bedOn(t), -60) {
            missedAt = t
            t = now
        }

        var items: [PlanItem] = []
        var dropped = false
        var catnapEnd: Date?
        for _ in 0..<6 {
            if t >= add(bedOn(t), -60) { break }
            var length = m.napLength(k + 1)
            let end = add(t, length)
            if add(end, m.window(pos + 1).0) > add(bedOn(t), 30) {
                if m.catnapHabit() {
                    length = m.catnapLength()
                    let ce = add(t, length)
                    catnapEnd = ce
                    items.append(PlanItem(kind: .nap, start: t, end: ce, catnap: true))
                    slept += length
                    wake = ce
                } else {
                    dropped = true
                }
                break
            }
            items.append(PlanItem(kind: .nap, start: t, end: end))
            k += 1
            pos += 1
            slept += length
            wake = end
            win = m.window(pos).0
            t = add(end, win)
        }

        // Sengetid (afsnit 3.3)
        let learned = m.learnedShift()
        var shift = learned > 0 && slept <= m.normalDaySleep() - deficit ? Double(learned) : 0
        var floor = shift == 0 ? t : add(wake, win * shortFactor)
        if let catnapEnd {
            shift = 0
            floor = add(catnapEnd, m.eveningGap() ?? m.window(pos + 1).0)
        } else if dropped {
            shift = maxBedShift
            floor = t
        }
        if missedAt != nil { floor = max(floor, now) }
        let bedtime = max(add(bedOn(t), -shift), floor)
        let bedShift = max(0, Int(mins(bedtime, bedOn(t)).rounded(.toNearestOrEven)))
        items.append(PlanItem(kind: .bedtime, start: bedtime))

        return DayPlan(items: items, wake: wakeAt, missedAt: missedAt, short: short, bedShift: bedShift,
                       firstWindow: Int(firstWin.rounded(.toNearestOrEven)), source: source, pos: firstPos,
                       bedBasis: m.evenings.count >= 3 ? .own : .default, naps: m.naps(), catnap: m.catnapHabit(),
                       lastID: last.id)
    }
}
