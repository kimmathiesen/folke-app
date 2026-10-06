import AppKit
import CoreGraphics

let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
// CoreGraphics har y opad: vend, så koordinaterne er som i SVG'en
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

// Nattehimmel (SKY kl. 22:30-24) med et svagt lilla skær øverst
let sky = CGGradient(colorsSpace: cs, colors: [c(0x1b2456), c(0x0e1430)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 1024), options: [])
let glow = CGGradient(colorsSpace: cs, colors: [c(0x7c6ff0, 0.38), c(0x7c6ff0, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 300), startRadius: 0, endCenter: CGPoint(x: 512, y: 300),
                       endRadius: 620, options: [])

// Logoets viewBox 100x100: indholdet (x 14-88, y 8-82) centreres
let k: CGFloat = 9.4
ctx.translateBy(x: 512 - 51 * k, y: 520 - 45 * k)
ctx.scaleBy(x: k, y: k)

// Halvmånen: cirkel r=34 om (58,29; 47,96) minus cirkel r=30,2 om (72,5; 41,5)
let moon = CGMutablePath()
moon.addEllipse(in: CGRect(x: 58.29 - 34, y: 47.96 - 34, width: 68, height: 68))
let bite = CGPath(ellipseIn: CGRect(x: 72.5 - 30.2, y: 41.5 - 30.2, width: 60.4, height: 60.4), transform: nil)
let crescent = moon.subtracting(bite)
let moonGrad = CGGradient(colorsSpace: cs, colors: [c(0x6ea0ff), c(0x8b7cf6)] as CFArray, locations: [0, 1])!
// Svag fyldning og en tyk kant i månens farver
ctx.saveGState()
ctx.addPath(crescent)
ctx.clip()
let fill = CGGradient(colorsSpace: cs, colors: [c(0x6ea0ff, 0.22), c(0x8b7cf6, 0.12)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(fill, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), options: [])
ctx.restoreGState()
func strokeGradient(_ path: CGPath, width: CGFloat) {
    ctx.saveGState()
    ctx.addPath(path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 4))
    ctx.clip()
    ctx.drawLinearGradient(moonGrad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), options: [])
    ctx.restoreGState()
}
strokeGradient(crescent, width: 3.6)
// Sovende ansigt
let smiles = CGMutablePath()
for (x, y, h) in [(46.0, 52.0, 3.0), (60, 58, 3), (52, 66, 2)] {
    smiles.move(to: CGPoint(x: x, y: y))
    smiles.addQuadCurve(to: CGPoint(x: x + 6, y: y), control: CGPoint(x: x + 3, y: y + h))
}
strokeGradient(smiles, width: 2.8)
// Stjerner
for pts in [[(82, 14), (83.8, 18.2), (88, 20), (83.8, 21.8), (82, 26), (80.2, 21.8), (76, 20), (80.2, 18.2)],
            [(18, 30), (19.3, 33), (22, 34.3), (19.3, 35.6), (18, 39), (16.7, 35.6), (14, 34.3), (16.7, 33)],
            [(30, 8), (31, 10.4), (33.4, 11.4), (31, 12.4), (30, 15), (29, 12.4), (26.6, 11.4), (29, 10.4)]] as [[(Double, Double)]] {
    let p = CGMutablePath()
    p.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) })
    p.closeSubpath()
    ctx.addPath(p)
    ctx.setFillColor(c(0xffe28a))
    ctx.fillPath()
}

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
