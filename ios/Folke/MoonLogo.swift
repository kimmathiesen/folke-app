import SwiftUI

/// Månen med stjerner øverst på forsiden (`#logo` i index.html, viewBox 100×100). Senere: genvej til tavlen.
struct MoonLogo: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.scaleBy(x: size.width / 100, y: size.height / 100)
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Color(hex: "#6ea0ff"), Color(hex: "#8b7cf6")]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 100, y: 100))
            ctx.stroke(Self.moon, with: shading, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            ctx.stroke(Self.smiles, with: shading, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            for star in Self.stars {
                ctx.fill(star, with: .color(Color(hex: "#ffe28a")))
            }
        }
        .frame(width: 84, height: 84)
        .accessibilityHidden(true)
    }

    /// Halvmånen: cirklen r=34 om (58,3; 48,0) minus cirklen r=30,2 om (72,5; 41,5),
    /// som er de to buer i SVG-stien «M60 14a34 34 0 1 0 25 55A30 30 0 0 1 60 14z».
    static let moon: Path = {
        let outer = Path(ellipseIn: CGRect(x: 58.29 - 34, y: 47.96 - 34, width: 68, height: 68))
        let inner = Path(ellipseIn: CGRect(x: 72.5 - 30.2, y: 41.5 - 30.2, width: 60.4, height: 60.4))
        return outer.subtracting(inner)
    }()

    static let smiles: Path = {
        var p = Path()
        for (x, y, h) in [(46.0, 52.0, 3.0), (60, 58, 3), (52, 66, 2)] {
            p.move(to: CGPoint(x: x, y: y))
            p.addQuadCurve(to: CGPoint(x: x + 6, y: y), control: CGPoint(x: x + 3, y: y + h))
        }
        return p
    }()

    static let stars: [Path] = [
        [(82, 14), (83.8, 18.2), (88, 20), (83.8, 21.8), (82, 26), (80.2, 21.8), (76, 20), (80.2, 18.2)],
        [(18, 30), (19.3, 33), (22, 34.3), (19.3, 35.6), (18, 39), (16.7, 35.6), (14, 34.3), (16.7, 33)],
        [(30, 8), (31, 10.4), (33.4, 11.4), (31, 12.4), (30, 15), (29, 12.4), (26.6, 11.4), (29, 10.4)],
    ].map { pts in
        var p = Path()
        p.addLines(pts.map { CGPoint(x: $0.0, y: $0.1) })
        p.closeSubpath()
        return p
    }
}
