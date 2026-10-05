import Foundation
import Testing
@testable import FolkeCore

/// Port af tests/test_who.py: WHO Child Growth Standards (2006), drenge, median (M) ved 0, 3, 6 og 12 mdr.
let medianBoys: [WHO.Measure: [Int: Double]] = [
    .weight: [0: 3.3464, 3: 6.3762, 6: 7.9340, 12: 9.6479],
    .length: [0: 49.8842, 3: 61.4292, 6: 67.6236, 12: 75.7488],
    .head: [0: 34.4618, 3: 40.5135, 6: 43.3306, 12: 46.0661],
]

struct MedianCase: CustomTestStringConvertible, Sendable {
    let kind: WHO.Measure, month: Int, median: Double
    var testDescription: String { "\(kind.rawValue) \(month) mdr." }
}

let cases: [MedianCase] = medianBoys.flatMap { k, ms in ms.map { MedianCase(kind: k, month: $0.key, median: $0.value) } }

@Suite("WHO") struct WHOTests {
    @Test(arguments: cases) func median(c: MedianCase) {
        #expect(abs(WHO.value(c.kind, .boy, month: Double(c.month), z: 0) - c.median) <= 1e-4)
    }

    @Test(arguments: cases) func kurveP50(c: MedianCase) {
        let row = WHO.curves(c.kind, .boy, upto: 12)[c.month]
        #expect(row.month == c.month)
        #expect(abs(row[.p50] - c.median) <= 0.005)
    }

    @Test(arguments: cases) func medianEr50Percentil(c: MedianCase) {
        #expect(WHO.percentile(c.kind, .boy, month: Double(c.month), value: c.median) == 50)
    }

    @Test func percentilgraenserVedFoedsel() {
        // WHO: drenge ved fødslen, P3 = 2,5 kg og P97 = 4,3 kg (afrundet)
        let row = WHO.curves(.weight, .boy, upto: 0)[0]
        #expect(abs(row[.p3] - 2.5) <= 0.05)
        #expect(abs(row[.p97] - 4.35) <= 0.05)
        #expect(row[.p3] < row[.p15] && row[.p15] < row[.p50] && row[.p50] < row[.p85] && row[.p85] < row[.p97])
    }

    @Test func interpolationMellemMaaneder() {
        let mid = WHO.value(.weight, .boy, month: 3.5, z: 0)
        #expect(medianBoys[.weight]![3]! < mid && mid < WHO.value(.weight, .boy, month: 4, z: 0))
    }

    @Test func percentilKlemmesOgUdenForOmraade() {
        #expect(WHO.percentile(.weight, .boy, month: 6, value: 30) == 99)
        #expect(WHO.percentile(.weight, .boy, month: 6, value: 3) == 1)
        #expect(WHO.percentile(.weight, .boy, month: 6, value: nil) == nil)
        #expect(WHO.percentile(.weight, .boy, month: -1, value: 5) == nil)
        #expect(WHO.percentile(.weight, .boy, month: 25, value: 12) == nil)
    }

    @Test func pigerHarEgneKurver() {
        #expect(WHO.value(.weight, .girl, month: 0, z: 0) < WHO.value(.weight, .boy, month: 0, z: 0))
    }

    // Ud over Python-testene

    @Test func tabellerneErKomplette() {
        for sex in Sex.allCases {
            for k in WHO.Measure.allCases {
                #expect(WHO.lms[sex]![k]!.count == 25)
            }
        }
    }

    @Test func kurvelaengdeFoelgerAlder() {
        #expect(WHO.chartMonths(ageMonths: 8.9) == 12)
        #expect(WHO.chartMonths(ageMonths: 9) == 24)
        #expect(WHO.curves(.length, .girl, upto: 24).count == 25)
    }
}
