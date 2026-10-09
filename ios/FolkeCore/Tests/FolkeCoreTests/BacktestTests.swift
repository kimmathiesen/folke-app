import Foundation
import Testing
@testable import FolkeCore

@Suite("Måling af forudsigelsen") struct BacktestTests {
    @Test func intervalSomEvaluatePy() {
        #expect(Backtest.interval([]) == (-20, 20))
        #expect(Backtest.interval([-30, -12, -5, 0, 3, 8, 15, 40]) == (-10, 13)) // samme som test_app.py
        #expect(Backtest.interval(Array(repeating: 2, count: 10)) == (-10, 10)) // mindst ±10
        #expect(Backtest.interval([-90, -80, -70, -60, 60, 70, 80, 90]) == (-45, 45)) // højst ±45
    }

    @Test func kvartilerSomPython() {
        let q = Backtest.quartiles([-30, -12, -5, 0, 3, 8, 15, 40])
        #expect(q.0 == -10.25 && q.1 == 1.5 && q.2 == 13.25) // statistics.quantiles(..., n=4)
    }

    @Test func faste_rytmerRammesPraecist() throws {
        // Den syntetiske historik har faste vinduer: efter de første 3 dage rammer forudsigelsen hver gang
        let res = Backtest.run(history(), birthDate: birth, calendar: cph)
        let s = try #require(Backtest.summary(res))
        #expect(s.n > 20 && s.medianAbs == 0 && s.within15 == 1)
    }

    @Test func spanEr10MinPaaHele5Min() {
        #expect(Format.span(at(day(2026, 6, 10), 11, 30), calendar: cph) == "kl. 11.25–11.35")
        #expect(Format.span(at(day(2026, 6, 10), 19, 53), calendar: cph) == "kl. 19.45–19.55")
        #expect(Format.span(at(day(2026, 6, 10), 19, 56), calendar: cph) == "kl. 19.50–20.00")
    }
}
