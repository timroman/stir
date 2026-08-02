import SwiftUI

// The clockless night face: the moon's actual daily track drawn as a full
// circle, the horizon as a line cutting through it, and the moon at its true
// position on the ring — dim below the horizon, bright above. The ring makes
// the position legible: you can watch the moon approach the rise or set
// crossing hours ahead. Position on the ring is the hour angle — astronomy,
// not the clock — so nothing on this screen correlates with the time of day.
// The warming sky gradient remains the sole "is it time yet" signal.
struct SkyFace: View {
    let moonPosition: MoonTracker.MoonPosition?
    let sunPosition: MoonTracker.MoonPosition?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let radius = min(w, h) * 0.34
            // One shared horizon; each body's circle is vertically offset so
            // its own rise/set chord lies exactly on the line. The fraction of
            // a ring above the line is the fraction of the day that body is up
            // — so the sun's ring rides high in summer while the moon's sits
            // low, and they trade places through the seasons.
            let horizonY = h * 0.5

            ZStack {
                // Ground: everything below the horizon
                Rectangle()
                    .fill(Color.black.opacity(0.16))
                    .frame(width: w, height: max(h - horizonY, 0))
                    .position(x: w / 2, y: horizonY + max(h - horizonY, 0) / 2)

                // Horizon line
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: w, height: 1)
                    .position(x: w / 2, y: horizonY)

                if let sun = sunPosition {
                    bodyTrack(sun, ringColor: NightSky.horizonAmber.opacity(0.18),
                              dotColor: NightSky.horizonAmber.opacity(0.35),
                              w: w, radius: radius, horizonY: horizonY) { point, below in
                        SunView(size: 26)
                            .position(point)
                            .opacity(below ? 0.35 : 1.0)
                    }
                }

                if let moon = moonPosition {
                    bodyTrack(moon, ringColor: Color.white.opacity(0.15),
                              dotColor: Color.white.opacity(0.3),
                              w: w, radius: radius, horizonY: horizonY) { point, below in
                        MoonPhaseView(size: 30)
                            .position(point)
                            .opacity(below ? 0.4 : 1.0)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    // A body's diurnal ring, its rise/set crossings, and the body itself
    @ViewBuilder
    private func bodyTrack<Body: View>(
        _ body: MoonTracker.MoonPosition,
        ringColor: Color, dotColor: Color,
        w: CGFloat, radius: CGFloat, horizonY: CGFloat,
        @ViewBuilder content: (CGPoint, Bool) -> Body
    ) -> some View {
        let center = CGPoint(x: w / 2, y: horizonY + radius * CGFloat(body.horizonCos))
        let point = CGPoint(
            x: center.x + radius * CGFloat(sin(body.hourAngle)),
            y: center.y - radius * CGFloat(cos(body.hourAngle))
        )

        Circle()
            .stroke(ringColor, lineWidth: 1.5)
            .frame(width: radius * 2, height: radius * 2)
            .position(center)

        if abs(body.horizonCos) < 1 {
            let dx = radius * CGFloat(sin(acos(body.horizonCos)))
            Circle().fill(dotColor).frame(width: 4, height: 4)
                .position(x: center.x - dx, y: horizonY)
            Circle().fill(dotColor).frame(width: 4, height: 4)
                .position(x: center.x + dx, y: horizonY)
        }

        content(point, point.y > horizonY)
    }
}

// A warm sun disc with a soft glow
struct SunView: View {
    var size: CGFloat = 26

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 0.98, green: 0.87, blue: 0.62),
                        Color(red: 0.94, green: 0.70, blue: 0.42)
                    ],
                    center: .init(x: 0.4, y: 0.35),
                    startRadius: 0, endRadius: size * 0.7
                )
            )
            .frame(width: size, height: size)
            .shadow(color: Color(red: 0.94, green: 0.70, blue: 0.42).opacity(0.45), radius: 12)
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
        SkyBackground(colors: NightSky.colors(NightSky.deepNight))
        SkyFace(
            moonPosition: MoonTracker.MoonPosition(
                altitude: 0.5, azimuth: -0.7, hourAngle: -0.9, horizonCos: 0.25
            ),
            sunPosition: MoonTracker.MoonPosition(
                altitude: -0.6, azimuth: 2.4, hourAngle: 2.6, horizonCos: -0.23
            )
        )
    }
}
