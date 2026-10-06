import Foundation
import Testing
@testable import FolkeCore

/// Tavlen (port af tests/test_board.py: streg, fortryd, visk ud, kontrol og version).
@MainActor @Suite("Tavlen", .serialized) struct BoardTests {
    let d = day(2026, 6, 10)

    func store() throws -> FolkeStore {
        let s = try FolkeStore(inMemory: true)
        s.calendar = cph
        try s.createChild(name: "Folke", birthDate: day(2026, 2, 1))
        return s
    }

    @Test func punkterGemmesOgLaesesIgen() {
        let pts: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(0.5, 0.25), SIMD2(1, 1)]
        #expect(Board.decode(Board.encode(pts)) == pts)
    }

    @Test func tegnFortrydOgVisKUd() throws {
        let s = try store()
        #expect(s.strokes().isEmpty && s.boardVersion() == 0)
        try s.addStroke(color: "#ff8fa3", points: [SIMD2(0.1, 0.1), SIMD2(0.2, 0.3)], by: .mor, now: at(d, 21, 0))
        try s.addStroke(color: "#8fb0ff", points: [SIMD2(0.5, 0.5)], by: .far, now: at(d, 21, 14))
        #expect(s.strokes().map(\.createdBy) == [.mor, .far])
        #expect(s.boardVersion() == at(d, 21, 14).timeIntervalSince1970)
        try s.undoStroke() // fortryd gælder også den andens streg
        #expect(s.strokes().map(\.color) == ["#ff8fa3"])
        try s.clearBoard()
        #expect(s.strokes().isEmpty && s.boardVersion() == 0)
    }

    @Test func kontrol() throws {
        let s = try store()
        #expect(throws: BoardError.invalidColor) { try s.addStroke(color: "#000000", points: [SIMD2(0, 0)], by: .mor) }
        #expect(throws: BoardError.invalidWidth) { try s.addStroke(color: "#f4f1ea", width: 0.1, points: [SIMD2(0, 0)], by: .mor) }
        #expect(throws: BoardError.invalidStroke) { try s.addStroke(color: "#f4f1ea", points: [], by: .mor) }
        #expect(throws: BoardError.invalidStroke) { try s.addStroke(color: "#f4f1ea", points: [SIMD2(1.5, 0)], by: .mor) }
        let many = [SIMD2<Float>](repeating: SIMD2(0.5, 0.5), count: 2000)
        for _ in 0..<15 { try s.addStroke(color: "#f4f1ea", points: many, by: .mor) }
        #expect(throws: BoardError.full) { try s.addStroke(color: "#f4f1ea", points: [SIMD2(0, 0)], by: .mor) }
    }
}
