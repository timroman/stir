import SwiftUI

// The clockless night face: the screen is the sky, and the only object in it
// is the real moon at its actual altitude and azimuth (bottom edge = horizon,
// facing south: east left, west right). Moon position doesn't correlate with
// the time of day — nothing on this screen does. The warming sky gradient is
// the sole "is it time yet" signal.
struct SkyFace: View {
    let moonPosition: MoonTracker.MoonPosition?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                if let moon = moonScreenPosition(w: w, h: h) {
                    MoonPhaseView(size: 30)
                        .position(moon.point)
                        .opacity(moon.opacity)
                }
            }
        }
        .ignoresSafeArea()
    }

    // Map real altitude/azimuth onto the screen. A moon within a few degrees
    // below the horizon shows faintly at the bottom edge — the catchable
    // rising/setting moment.
    private func moonScreenPosition(w: CGFloat, h: CGFloat) -> (point: CGPoint, opacity: Double)? {
        guard let moon = moonPosition else { return nil }

        let altDeg = moon.altitude * 180 / .pi
        guard altDeg > -6 else { return nil }

        let azDeg = moon.azimuth * 180 / .pi
        let xFraction = min(max((azDeg + 90) / 180, 0), 1)
        let x = 28 + (w - 56) * xFraction

        let horizonY = h - 40
        let topY = h * 0.12
        let altFraction = min(max(altDeg / 75, 0), 1)
        let y = horizonY - (horizonY - topY) * altFraction

        let opacity = altDeg < 4 ? 0.35 + 0.65 * (altDeg + 6) / 10 : 1.0
        return (CGPoint(x: x, y: min(y, horizonY)), opacity)
    }
}

// Tonight's actual lunar phase, computed from the synodic period — no API,
// no location, no permission.
struct MoonPhaseView: View {
    var size: CGFloat = 26
    var date: Date = Date()

    var body: some View {
        let phase = Self.phaseFraction(date: date)
        ZStack {
            // Earthshine disc
            Circle()
                .fill(Color(red: 0.30, green: 0.31, blue: 0.36))

            LitShape(phase: phase)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.95, green: 0.92, blue: 0.84),
                            Color(red: 0.79, green: 0.75, blue: 0.66)
                        ],
                        center: .init(x: 0.4, y: 0.35),
                        startRadius: 0, endRadius: size * 0.7
                    )
                )
        }
        .frame(width: size, height: size)
        .shadow(color: NightSky.cream.opacity(0.3), radius: 10)
    }

    // 0 = new, 0.5 = full, wrapping at 1
    static func phaseFraction(date: Date) -> Double {
        let knownNewMoon = Date(timeIntervalSince1970: 947_182_440) // 2000-01-06 18:14 UTC
        let synodic = 29.530588 * 86_400.0
        let elapsed = date.timeIntervalSince(knownNewMoon).truncatingRemainder(dividingBy: synodic)
        return (elapsed < 0 ? elapsed + synodic : elapsed) / synodic
    }

    // Lit portion: a semicircle on the lit side closed by the terminator,
    // a half-ellipse whose signed horizontal radius follows the phase.
    private struct LitShape: Shape {
        let phase: Double

        func path(in rect: CGRect) -> Path {
            let r = rect.width / 2
            let cx = rect.midX
            let cy = rect.midY
            let waxing = phase < 0.5
            let p = waxing ? phase : 1 - phase
            // +r at new (terminator hugs the limb, thin sliver) through 0 at
            // quarter (straight diameter) to -r at full (nearly whole disc)
            let rx = CGFloat(cos(2 * .pi * p)) * r
            // Cubic approximation of a half-ellipse
            let k: CGFloat = 1.3333 * rx

            var path = Path()
            let top = CGPoint(x: cx, y: cy - r)
            let bottom = CGPoint(x: cx, y: cy + r)
            path.move(to: top)
            // Limb on the lit side
            path.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                        startAngle: .degrees(-90), endAngle: .degrees(90),
                        clockwise: false)
            // Terminator back to the top
            path.addCurve(to: top,
                          control1: CGPoint(x: cx + k, y: bottom.y),
                          control2: CGPoint(x: cx + k, y: top.y))
            if !waxing {
                // Waning: lit side is the left — mirror horizontally
                path = path.applying(
                    CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -rect.width, y: 0)
                )
            }
            return path
        }
    }
}

#Preview("Sky face") {
    ZStack {
        SkyBackground(colors: NightSky.colors(NightSky.preDawn))
        SkyFace(moonPosition: MoonTracker.MoonPosition(altitude: 0.5, azimuth: -0.7))
    }
}
