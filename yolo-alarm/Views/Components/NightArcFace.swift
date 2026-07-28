import SwiftUI

// The clockless night face. The arc is the night's *plan* — phase-colored
// segments from bedtime to "up by" — with no marker for the current moment:
// nothing on this screen represents the time. The sun cresting the right
// horizon is the only "is it time yet" signal. The moon is the real moon:
// rendered at its actual altitude and azimuth, so when it touches the horizon
// line here, it's rising or setting outside the window.
struct NightArcFace: View {
    let now: Date
    let sessionStart: Date
    let upBy: Date
    let fadeStart: Date
    let whiteNoiseEnd: Date
    let windowStart: Date
    let whiteNoiseEnabled: Bool
    let alarmEnabled: Bool
    let moonPosition: MoonTracker.MoonPosition?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Base arc, faint
                NightArcShape()
                    .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                // The night's plan, phase-colored
                ForEach(segments, id: \.from) { segment in
                    NightArcShape()
                        .trim(from: segment.from, to: segment.to)
                        .stroke(segment.color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }

                // The sun waits below the right horizon and crests into the wake window
                if sunProgress > 0 {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.96, green: 0.80, blue: 0.55),
                                    Color(red: 0.94, green: 0.66, blue: 0.42).opacity(0.55),
                                    .clear
                                ],
                                center: .center, startRadius: 2, endRadius: 34
                            )
                        )
                        .frame(width: 68, height: 68)
                        .position(x: arcPoint(1, w: w, h: h).x,
                                  y: arcPoint(1, w: w, h: h).y + 26 - 30 * sunProgress)
                        .opacity(0.35 + 0.65 * sunProgress)
                }

                // The real moon, where it actually is in the sky
                if let moonPoint = moonScreenPosition(w: w, h: h) {
                    MoonPhaseView(size: 26)
                        .position(moonPoint.point)
                        .opacity(moonPoint.opacity)
                }
            }
        }
    }

    private var night: TimeInterval { upBy.timeIntervalSince(sessionStart) }

    private func fraction(_ date: Date) -> Double {
        guard night > 0 else { return 1 }
        return min(max(date.timeIntervalSince(sessionStart) / night, 0), 1)
    }

    // Map the moon's real altitude/azimuth into the face. Facing south:
    // east (moonrise) on the left edge, west (moonset) on the right, the arc's
    // baseline as the horizon. A moon within a few degrees below the horizon
    // shows faintly at the line — the catchable rising/setting moment.
    private func moonScreenPosition(w: CGFloat, h: CGFloat) -> (point: CGPoint, opacity: Double)? {
        guard let moon = moonPosition else { return nil }

        let altDeg = moon.altitude * 180 / .pi
        guard altDeg > -6 else { return nil }  // well below the horizon: not shown

        // Azimuth from south, west positive; clamp east/west extremes to edges
        let azDeg = moon.azimuth * 180 / .pi
        let xFraction = min(max((azDeg + 90) / 180, 0), 1)
        let x = 16 + (w - 32) * xFraction

        let horizonY = h - 6
        let topY: CGFloat = 10
        let altFraction = min(max(altDeg / 75, 0), 1)
        let y = horizonY - (horizonY - topY) * altFraction

        // Fade in through the horizon-crossing band
        let opacity = altDeg < 4 ? 0.35 + 0.65 * (altDeg + 6) / 10 : 1.0
        return (CGPoint(x: x, y: min(y, horizonY)), opacity)
    }

    private struct Segment {
        let from: Double
        let to: Double
        let color: Color
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        if whiteNoiseEnabled {
            result.append(Segment(from: 0, to: fraction(fadeStart), color: NightSky.cream.opacity(0.55)))
            result.append(Segment(from: fraction(fadeStart), to: fraction(whiteNoiseEnd), color: NightSky.cream.opacity(0.28)))
        }
        if alarmEnabled {
            // Quiet gap stays near-invisible; the wake window glows dawn amber
            result.append(Segment(from: fraction(windowStart), to: 1, color: NightSky.dawnAmber.opacity(0.85)))
        } else {
            result.append(Segment(from: fraction(whiteNoiseEnd), to: 1, color: NightSky.dawnAmber.opacity(0.5)))
        }
        return result
    }

    // 0 before the sun starts rising, 1 at "up by"
    private var sunProgress: Double {
        let riseStart = alarmEnabled ? windowStart : fadeStart
        let span = upBy.timeIntervalSince(riseStart)
        guard span > 0 else { return now >= upBy ? 1 : 0 }
        return min(max(now.timeIntervalSince(riseStart) / span, 0), 1)
    }

    private func arcPoint(_ t: Double, w: CGFloat, h: CGFloat) -> CGPoint {
        let p0 = CGPoint(x: 6, y: h - 6)
        let c = CGPoint(x: w / 2, y: -h * 0.55)
        let p1 = CGPoint(x: w - 6, y: h - 6)
        let mt = 1 - t
        let x = mt * mt * p0.x + 2 * mt * t * c.x + t * t * p1.x
        let y = mt * mt * p0.y + 2 * mt * t * c.y + t * t * p1.y
        return CGPoint(x: x, y: y)
    }
}

struct NightArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 6, y: rect.height - 6))
        path.addQuadCurve(
            to: CGPoint(x: rect.width - 6, y: rect.height - 6),
            control: CGPoint(x: rect.width / 2, y: -rect.height * 0.55)
        )
        return path
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

#Preview("Night face") {
    ZStack {
        SkyBackground(colors: NightSky.colors(NightSky.deepNight))
        NightArcFace(
            now: Date().addingTimeInterval(3600 * 3),
            sessionStart: Date(),
            upBy: Date().addingTimeInterval(3600 * 8),
            fadeStart: Date().addingTimeInterval(3600 * 6.5),
            whiteNoiseEnd: Date().addingTimeInterval(3600 * 7),
            windowStart: Date().addingTimeInterval(3600 * 7.5),
            whiteNoiseEnabled: true,
            alarmEnabled: true,
            moonPosition: MoonTracker.MoonPosition(altitude: 0.6, azimuth: -0.8)
        )
        .frame(height: 140)
        .padding(.horizontal, 30)
    }
}
