import Foundation
import Testing
@testable import FolkeCore

/// Eksport som CSV (PLAN.md milepæl 10).
@MainActor @Suite("Eksport som CSV", .serialized) struct ExportTests {
    let d = day(2026, 6, 10)

    @Test func fireFilerMedDanskeOverskrifterOgDecimalkomma() throws {
        let s = try FolkeStore(inMemory: true)
        s.calendar = cph
        try s.createChild(name: "Folke", birthDate: day(2026, 2, 1))
        try s.startSleep(by: .mor, now: at(d, 12, 0))
        try s.stopSleep(nap: true, now: at(d, 13, 30))
        try s.addFeeding(.bottle, amountMl: 120, milk: .formula, at: at(d, 14, 5), now: at(d, 15, 0))
        try s.addFeeding(.solid, note: "grød; med \"æble\"", at: at(d, 14, 30), now: at(d, 15, 0))
        try s.addPumping(amountMl: 95.5, side: .left, minutes: 15, at: at(d, 9, 0), now: at(d, 15, 0))
        try s.saveGrowth(date: d, values: [.weight: 6.25, .length: 62], now: at(d, 15, 0))

        let files = s.csvExport(now: at(d, 15, 0))
        #expect(files.map(\.name) == ["folke-soevn-2026-06-10.csv", "folke-mad-2026-06-10.csv",
                                      "folke-udpumpning-2026-06-10.csv", "folke-vaekst-2026-06-10.csv"])
        #expect(files[0].text == "Barn;Start;Slut;Minutter;Type;Opvågninger;Vågen (min)\r\nFolke;2026-06-10 12:00;2026-06-10 13:30;90;Lur;;\r\n")
        #expect(files[1].text.contains("Folke;2026-06-10 14:05;Flaske;120;Modermælkserstatning;\r\n"))
        #expect(files[1].text.contains("Folke;2026-06-10 14:30;Fast føde;;;\"grød; med \"\"æble\"\"\"\r\n"))
        #expect(files[2].text.hasSuffix("2026-06-10 09:00;95,5;venstre;15\r\n"))
        #expect(files[3].text.hasSuffix("Folke;2026-06-10;6,25;62;\r\n"))
        #expect(files.map(\.rows) == [1, 2, 1, 1])
        #expect(files[0].data.prefix(3) == Data([0xEF, 0xBB, 0xBF]))
    }

    @Test func soevnIGangHarIngenSlut() throws {
        let s = try FolkeStore(inMemory: true)
        s.calendar = cph
        try s.createChild(name: "Folke", birthDate: day(2026, 2, 1))
        try s.startSleep(by: .far, now: at(d, 19, 30))
        #expect(s.csvExport(now: at(d, 20, 0))[0].text.hasSuffix("Folke;2026-06-10 19:30;;;Nat;;\r\n"))
    }

    @Test func nattensOpvaagningerIEksporten() throws {
        let s = try FolkeStore(inMemory: true)
        s.calendar = cph
        try s.createChild(name: "Folke", birthDate: day(2026, 2, 1), now: d)
        try s.startSleep(by: .mor, now: at(d, 19, 30))
        try s.startWake(by: .mor, now: at(d, 23, 0))
        try s.stopWake(now: at(d, 23, 25))
        try s.stopSleep(nap: false, now: at(plusDays(d, 1), 6, 30))
        #expect(s.csvExport(now: at(plusDays(d, 1), 7, 0))[0].text.hasSuffix(";Nat;1;25\r\n"))
    }
}
