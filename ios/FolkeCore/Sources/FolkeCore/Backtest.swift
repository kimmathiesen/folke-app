import Foundation

/// Måling af forudsigelsen mod historikken (port af `evaluate.py`). For hver søvn: lad som om klokken er lige efter,
/// han vågnede sidst, regn forudsigelsen ud fra det, der var registreret indtil da, og sammenlign med det tidspunkt,
/// han faktisk faldt i søvn. Fejl i minutter: positiv = han faldt i søvn senere end forudsagt.
public enum Backtest {
    public static let minHistoryDays = 3.0

    public struct Result: Equatable, Sendable {
        public var at: Date
        public var actual: Prediction.Kind
        public var predicted: Prediction.Kind
        public var error: Double
    }

    public struct Summary: Equatable, Sendable {
        public var n: Int
        public var medianAbs: Double
        public var within15: Double
        public var within30: Double
        /// Tidligst og senest i minutter omkring forudsigelsen
        public var interval: (lo: Int, hi: Int)

        public static func == (a: Summary, b: Summary) -> Bool {
            a.n == b.n && a.medianAbs == b.medianAbs && a.within15 == b.within15 && a.within30 == b.within30
                && a.interval == b.interval
        }
    }

    public typealias Predict = ([SleepSample], Date, Date) -> Prediction?

    public static func run(_ sleeps: [SleepSample], birthDate: Date, historyDays: Int = Predictor.historyDays,
                           calendar: Calendar = .current, predict: Predict? = nil) -> [Result] {
        let predict = predict ?? { Predictor.predict($0, birthDate: $1, now: $2, calendar: calendar) }
        let sleeps = sleeps.sorted { $0.start < $1.start }
        guard let first = sleeps.first?.start else { return [] }
        var out: [Result] = []
        for (i, s) in sleeps.enumerated() {
            let prev = sleeps[..<i].filter { $0.end <= s.start }
            guard let last = prev.last, s.start.timeIntervalSince(first) >= minHistoryDays * 86400 else { continue }
            let now = last.end.addingTimeInterval(60)
            if s.start.timeIntervalSince(now) > 8 * 3600 { continue } // et hul i registreringerne
            let hist = prev.filter { $0.end >= now.addingTimeInterval(-Double(historyDays) * 86400) }
            guard let p = predict(Array(hist), birthDate, now) else { continue }
            out.append(Result(at: s.start, actual: s.nap ? .nap : .bedtime, predicted: p.kind,
                              error: s.start.timeIntervalSince(p.time) / 60))
        }
        return out
    }

    public static func summary(_ results: [Result]) -> Summary? {
        guard !results.isEmpty else { return nil }
        let abs = results.map { Swift.abs($0.error) }
        func share(_ limit: Double) -> Double {
            (Double(abs.filter { $0 <= limit }.count) / Double(abs.count) * 100).rounded() / 100
        }
        return Summary(n: results.count, medianAbs: (Predictor.median(abs) * 10).rounded() / 10,
                       within15: share(15), within30: share(30), interval: interval(results.map(\.error)))
    }

    /// Den midterste halvdel af fejlene (25.-75. percentil), dog mindst ±10 og højst ±45 min; ±20 med under 8 målinger.
    public static func interval(_ errors: [Double], minHalf: Double = 10, maxHalf: Double = 45) -> (lo: Int, hi: Int) {
        guard errors.count >= 8 else { return (-20, 20) }
        let q = quartiles(errors)
        let lo = min(q.0, -minHalf), hi = max(q.2, minHalf)
        return (Int(max(lo.rounded(.toNearestOrEven), -maxHalf)), Int(min(hi.rounded(.toNearestOrEven), maxHalf)))
    }

    /// Som Pythons `statistics.quantiles(data, n=4)` (metoden «exclusive»).
    static func quartiles(_ values: [Double]) -> (Double, Double, Double) {
        let d = values.sorted(), m = d.count + 1
        func q(_ i: Int) -> Double {
            let j = min(max(i * m / 4, 1), d.count - 1)
            let delta = Double(i * m - (i * m / 4) * 4)
            return (d[j - 1] * (4 - delta) + d[j] * delta) / 4
        }
        return (q(1), q(2), q(3))
    }
}

public extension FolkeStore {
    /// Hvor godt forudsigelsen har ramt de seneste 14 dage (dagsplanen med Plus, ellers den enkle forudsigelse).
    func accuracy(plus: Bool = true, now: Date = .now) -> Backtest.Summary? {
        guard let birth = child()?.birthDate else { return nil }
        let samples = sleeps(since: now.addingTimeInterval(-Double(14 + Predictor.historyDays) * 86400)).compactMap(\.sample)
        let cal = calendar
        let predict: Backtest.Predict = plus
            ? { Predictor.predict($0, birthDate: $1, now: $2, calendar: cal) }
            : { Predictor.basic($0, birthDate: $1, now: $2, calendar: cal) }
        let res = Backtest.run(samples, birthDate: birth, calendar: cal, predict: predict)
            .filter { $0.at >= now.addingTimeInterval(-14 * 86400) }
        return Backtest.summary(res) ?? Backtest.Summary(n: 0, medianAbs: 0, within15: 0, within30: 0, interval: (-20, 20))
    }
}

public extension Format {
    /// «kl. 11.15–11.45»: forudsigelsen med intervallet, afrundet udad til hele 5 minutter
    static func span(_ t: Date, _ interval: (lo: Int, hi: Int), calendar: Calendar = .current) -> String {
        let x = t.timeIntervalSinceReferenceDate
        let lo = (((x + Double(interval.lo) * 60) / 300).rounded(.down)) * 300
        let hi = (((x + Double(interval.hi) * 60) / 300).rounded(.up)) * 300
        return "kl. \(time(Date(timeIntervalSinceReferenceDate: lo), calendar: calendar))–"
            + "\(time(Date(timeIntervalSinceReferenceDate: hi), calendar: calendar))"
    }
}
