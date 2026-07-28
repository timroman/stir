import SwiftUI

// The living sky: one gradient that tracks the night. Palettes are keyframes;
// the current sky is interpolated from time remaining until "up by", so the
// horizon warms as sunrise approaches.
enum NightSky {
    typealias RGB = (r: Double, g: Double, b: Double)

    // Top-to-bottom gradient stops (zenith → horizon)
    static let dusk: [RGB] = [
        (0.10, 0.13, 0.27), (0.14, 0.18, 0.36), (0.23, 0.25, 0.43), (0.43, 0.33, 0.44)
    ]
    static let deepNight: [RGB] = [
        (0.03, 0.04, 0.11), (0.05, 0.08, 0.18), (0.09, 0.13, 0.29), (0.14, 0.17, 0.33)
    ]
    static let preDawn: [RGB] = [
        (0.04, 0.06, 0.14), (0.09, 0.14, 0.30), (0.20, 0.25, 0.43), (0.48, 0.35, 0.42)
    ]
    static let dawn: [RGB] = [
        (0.06, 0.09, 0.21), (0.16, 0.21, 0.38), (0.36, 0.31, 0.47), (0.82, 0.60, 0.42)
    ]
    static let sunrise: [RGB] = [
        (0.14, 0.19, 0.36), (0.33, 0.31, 0.49), (0.70, 0.48, 0.38), (0.94, 0.73, 0.50)
    ]

    // Shared accents
    static let cream = Color(red: 0.95, green: 0.92, blue: 0.84)       // moonlight
    static let dawnAmber = Color(red: 0.91, green: 0.79, blue: 0.63)   // status accent
    static let horizonAmber = Color(red: 0.82, green: 0.60, blue: 0.42)
    static let dawnAmberComponents: (red: Double, green: Double, blue: Double) = (0.91, 0.79, 0.63)

    private static func lerp(_ a: [RGB], _ b: [RGB], _ t: Double) -> [Color] {
        let t = min(max(t, 0), 1)
        return zip(a, b).map { p, q in
            Color(red: p.r + (q.r - p.r) * t,
                  green: p.g + (q.g - p.g) * t,
                  blue: p.b + (q.b - p.b) * t)
        }
    }

    static func colors(_ palette: [RGB]) -> [Color] {
        palette.map { Color(red: $0.r, green: $0.g, blue: $0.b) }
    }

    // The sky for a moment in the night. Deep night for most of the session,
    // warming through pre-dawn and dawn as "up by" approaches, then to full
    // sunrise in the 20 minutes after it. A fresh session settles from dusk
    // into deep night over the first 45 minutes.
    static func colors(now: Date, sessionStart: Date, upBy: Date) -> [Color] {
        let remaining = upBy.timeIntervalSince(now)

        let base: [Color]
        if remaining <= 0 {
            base = lerp(dawn, sunrise, -remaining / 1200)
        } else if remaining <= 1200 {          // last 20 min: pre-dawn → dawn
            base = lerp(preDawn, dawn, 1 - remaining / 1200)
        } else if remaining <= 5400 {          // 90 → 20 min out: night → pre-dawn
            base = lerp(deepNight, preDawn, 1 - (remaining - 1200) / 4200)
        } else {
            base = colors(deepNight)
        }

        // Settle from dusk into the night sky after bedtime
        let elapsed = now.timeIntervalSince(sessionStart)
        if elapsed < 2700, remaining > 0 {
            let settled = base
            let duskColors = colors(dusk)
            let t = max(elapsed / 2700, 0)
            return zip(duskColors, settled).map { d, s in
                blend(d, s, t)
            }
        }
        return base
    }

    private static func blend(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let ca = UIColor(a), cb = UIColor(b)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        ca.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        cb.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return Color(red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t)
    }
}

struct SkyBackground: View {
    let colors: [Color]

    var body: some View {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

#Preview("Deep night") {
    SkyBackground(colors: NightSky.colors(NightSky.deepNight))
}

#Preview("Dawn") {
    SkyBackground(colors: NightSky.colors(NightSky.dawn))
}
