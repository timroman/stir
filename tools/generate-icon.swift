import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let size: CGFloat = 1024
let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                    bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Night sky: near-black
ctx.setFillColor(CGColor(red: 0.02, green: 0.024, blue: 0.03, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// CG origin is bottom-left; design in top-left terms via flip
func Y(_ y: CGFloat) -> CGFloat { size - y }

let horizonY: CGFloat = 512      // design coords from top
let ringR: CGFloat = 300
let cx: CGFloat = 512

// Nebula washes, barely there
func nebula(_ cx: CGFloat, _ cy: CGFloat, _ radius: CGFloat, _ color: CGColor) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                       colors: [color, CGColor(red: 0, green: 0, blue: 0, alpha: 0)] as CFArray,
                       locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: cx, y: Y(cy)), startRadius: 0,
                           endCenter: CGPoint(x: cx, y: Y(cy)), endRadius: radius, options: [])
}
nebula(790, 210, 330, CGColor(red: 0.20, green: 0.12, blue: 0.32, alpha: 0.30))
nebula(180, 420, 300, CGColor(red: 0.08, green: 0.14, blue: 0.30, alpha: 0.25))

// Seeded starfield (SplitMix64) — denser above the horizon, sparse below
var rngState: UInt64 = 20260802
func rnd() -> CGFloat {
    rngState = rngState &+ 0x9E3779B97F4A7C15
    var z = rngState
    z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
    z = z ^ (z >> 31)
    return CGFloat(z >> 11) / CGFloat(1 << 53)
}
for _ in 0..<150 {
    let x = rnd() * size
    let y = rnd() * size
    let belowHorizon = y > 512
    if belowHorizon && rnd() > 0.3 { continue }   // sparse under the ground line
    let b = rnd()
    let r = 1.2 + pow(b, 3) * 4.5
    let roll = rnd()
    let tint: (CGFloat, CGFloat, CGFloat) = roll < 0.78 ? (0.95, 0.93, 0.87)
        : roll < 0.92 ? (0.75, 0.82, 0.98) : (0.95, 0.78, 0.55)
    let alpha = (0.18 + b * 0.55) * (belowHorizon ? 0.5 : 1.0)
    if r > 4.0 {
        ctx.setFillColor(CGColor(red: tint.0, green: tint.1, blue: tint.2, alpha: alpha * 0.15))
        ctx.fillEllipse(in: CGRect(x: x - r * 3, y: Y(y) - r * 3, width: r * 6, height: r * 6))
    }
    ctx.setFillColor(CGColor(red: tint.0, green: tint.1, blue: tint.2, alpha: alpha))
    ctx.fillEllipse(in: CGRect(x: x - r, y: Y(y) - r, width: r * 2, height: r * 2))
}

// Ground below the horizon, faintly lighter
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.05))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: Y(horizonY)))

// Moon ring rides high tonight (moon up), sun ring rides low (sun down)
let moonCy: CGFloat = horizonY - 85   // center above horizon
let sunCy: CGFloat = horizonY + 85    // center below horizon

// Sun ring (amber, faint)
ctx.setStrokeColor(CGColor(red: 0.82, green: 0.60, blue: 0.42, alpha: 0.5))
ctx.setLineWidth(14)
ctx.strokeEllipse(in: CGRect(x: cx - ringR, y: Y(sunCy) - ringR, width: ringR * 2, height: ringR * 2))

// Moon ring (cream, faint)
ctx.setStrokeColor(CGColor(red: 0.93, green: 0.90, blue: 0.87, alpha: 0.32))
ctx.strokeEllipse(in: CGRect(x: cx - ringR, y: Y(moonCy) - ringR, width: ringR * 2, height: ringR * 2))

// Horizon line over the rings
ctx.setStrokeColor(CGColor(red: 0.93, green: 0.90, blue: 0.87, alpha: 0.30))
ctx.setLineWidth(10)
ctx.move(to: CGPoint(x: 0, y: Y(horizonY)))
ctx.addLine(to: CGPoint(x: size, y: Y(horizonY)))
ctx.strokePath()

// The sun: on its ring, below the horizon, dimmed — it's night
let sunAngle: CGFloat = .pi * 0.72   // low on the ring, left of bottom
let sunX = cx + ringR * sin(sunAngle)
let sunY = sunCy + ringR * cos(sunAngle) * -1 + 0
// place on lower arc: use angle from top; pick point on lower-left arc
let sx = cx - ringR * 0.55
let sy = sunCy + ringR * 0.835
ctx.setFillColor(CGColor(red: 0.82, green: 0.60, blue: 0.42, alpha: 0.55))
ctx.fillEllipse(in: CGRect(x: sx - 52, y: Y(sy) - 52, width: 104, height: 104))
_ = (sunX, sunY)

// The moon: high on its ring, bright, with a soft glow
let mx = cx + ringR * 0.45
let my = moonCy - ringR * 0.893
let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                      colors: [CGColor(red: 0.95, green: 0.92, blue: 0.84, alpha: 0.35),
                               CGColor(red: 0.95, green: 0.92, blue: 0.84, alpha: 0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: mx, y: Y(my)), startRadius: 0,
                       endCenter: CGPoint(x: mx, y: Y(my)), endRadius: 190, options: [])
ctx.setFillColor(CGColor(red: 0.95, green: 0.92, blue: 0.84, alpha: 1))
ctx.fillEllipse(in: CGRect(x: mx - 78, y: Y(my) - 78, width: 156, height: 156))

let img = ctx.makeImage()!
let out = CommandLine.arguments[1]
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
