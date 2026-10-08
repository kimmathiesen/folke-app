import CoreData
import Foundation

/// En streg på tavlen. Punkterne er i 0..1 på en tavle med fast format 3:4, så den ser ens ud overalt.
public struct BoardStroke: Equatable, Sendable {
    public var id: UUID
    public var color: String
    /// Stregtykkelse som andel af tavlens bredde
    public var width: Double
    public var points: [SIMD2<Float>]
    public var createdAt: Date
    public var createdBy: Role?
}

public enum BoardError: Error, Equatable, LocalizedError {
    case invalidColor, invalidWidth, invalidStroke, full

    public var errorDescription: String? {
        switch self {
        case .invalidColor: "Ugyldig farve"
        case .invalidWidth: "Ugyldig stregtykkelse"
        case .invalidStroke: "Ugyldig streg"
        case .full: "Tavlen er fuld. Visk ud først"
        }
    }
}

/// Tavlen (PLAN.md afsnit 5, «Tavlen»; port af /api/board i app.py). Én post pr. streg, så to forældre aldrig
/// skriver i samme post. Fortryd og «Visk ud» gælder for begge.
public enum Board {
    public static let colors = Theme.boardColors
    public static let strokeWidth = 0.012
    public static let maxPoints = 2000
    public static let maxTotal = 30000

    /// [x, y] som Float32 (little endian) efter hinanden
    public static func encode(_ points: [SIMD2<Float>]) -> Data {
        var data = Data(capacity: points.count * 8)
        for p in points {
            withUnsafeBytes(of: p.x.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: p.y.bitPattern.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    public static func decode(_ data: Data) -> [SIMD2<Float>] {
        let bytes = [UInt8](data)
        var out: [SIMD2<Float>] = []
        out.reserveCapacity(bytes.count / 8)
        func f(_ i: Int) -> Float {
            Float(bitPattern: UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24)
        }
        var i = 0
        while i + 8 <= bytes.count {
            out.append(SIMD2(f(i), f(i + 4)))
            i += 8
        }
        return out
    }
}

public extension FolkeStore {
    /// Familiens streger, ældste først.
    func strokes() -> [BoardStroke] {
        fetch(Stroke.self, forFamily(), sort: [NSSortDescriptor(key: "createdAt", ascending: true)]).compactMap { s in
            guard let id = s.id, let color = s.color, let at = s.createdAt else { return nil }
            return BoardStroke(id: id, color: color, width: s.width, points: Board.decode(s.points ?? Data()),
                               createdAt: at, createdBy: s.createdBy.flatMap(Role.init(rawValue:)))
        }
    }

    /// Tegn en streg (samme kontrol som `clean_stroke` i app.py).
    @discardableResult
    func addStroke(color: String, width: Double = Board.strokeWidth, points: [SIMD2<Float>], by role: Role?,
                   now: Date = .now) throws -> BoardStroke {
        guard Board.colors.contains(color) else { throw BoardError.invalidColor }
        guard (0.003...0.05).contains(width) else { throw BoardError.invalidWidth }
        guard (1...Board.maxPoints).contains(points.count),
              points.allSatisfy({ (0...1).contains($0.x) && (0...1).contains($0.y) }) else { throw BoardError.invalidStroke }
        let total = fetch(Stroke.self, forFamily()).reduce(0) { $0 + ($1.points?.count ?? 0) / 8 }
        guard total + points.count <= Board.maxTotal else { throw BoardError.full }
        let fam = family()
        let s = insert(Stroke.self, child: nil)
        if let store = fam?.objectID.persistentStore { context.assign(s, to: store) }
        s.id = UUID()
        s.color = color
        s.width = width
        s.points = Board.encode(points.map { SIMD2((($0.x * 1e4).rounded() / 1e4), (($0.y * 1e4).rounded() / 1e4)) })
        s.createdAt = now
        s.createdBy = role?.rawValue
        s.family = fam
        try save()
        return BoardStroke(id: s.id!, color: color, width: width, points: points, createdAt: now, createdBy: role)
    }

    /// Fortryd seneste streg (uanset hvem der tegnede den).
    func undoStroke() throws {
        if let last = fetch(Stroke.self, forFamily(), sort: [NSSortDescriptor(key: "createdAt", ascending: false)], limit: 1).first {
            try delete(last)
        }
    }

    /// Visk tavlen ud.
    func clearBoard() throws {
        for s in fetch(Stroke.self, forFamily()) { context.delete(s) }
        try save()
    }

    /// Version til «nyt på tavlen»: tidspunktet for seneste streg (0, når tavlen er tom).
    func boardVersion() -> Double {
        fetch(Stroke.self, forFamily(), sort: [NSSortDescriptor(key: "createdAt", ascending: false)], limit: 1).first?
            .createdAt?.timeIntervalSince1970 ?? 0
    }
}
