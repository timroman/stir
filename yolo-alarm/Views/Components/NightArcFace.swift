import SwiftUI

// The clockless night face: the whole night drawn as a horizon arc. The moon
// is the "now" marker traveling from bedtime (left) to "up by" (right); the
// traveled arc dims behind it, phases color the segments, and the sun crests
// the right horizon as the wake window opens. Where the moon sits — and how
// warm the sky is — answers "is it time yet" without a numeral on screen.
struct NightArcFace: View {
    let now: Date
    let sessionStart: Date
    let upBy: Date
    let fadeStart: Date
    let whiteNoiseEnd: Date
    let windowStart: Date
    let whiteNoiseEnabled: Bool
    let alarmEnabled: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Base arc, faint
                NightArcShape()
                    .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                // Phase segments over the remaining night
                ForEach(segments, id: \.from) { segment in
                    NightArcShape()
                        .trim(from: max(segment.from, tNow), to: segment.to)
                        .stroke(segment.color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }

                // Traveled night, barely there
                NightArcShape()
                    .trim(from: 0, to: tNow)
                    .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 2, lineCap: .round))

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

                // The moon is "now" — tonight's real phase
                MoonPhaseView(size: 26)
                    .position(arcPoint(tNow, w: w, h: h))
            }
        }
    }

    private var night: TimeInterval { upBy.timeIntervalSince(sessionStart) }

    private var tNow: Double {
        guard night > 0 else { return 1 }
        return min(max(now.timeIntervalSince(sessionStart) / night, 0), 1)
    }

    private func fraction(_ date: Date) -> Double {
        guard night > 0 else { return 1 }
        return min(max(date.timeIntervalSince(sessionStart) / night, 0), 1)
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
            alarmEnabled: true
        )
        .frame(height: 140)
        .padding(.horizontal, 30)
    }
}
