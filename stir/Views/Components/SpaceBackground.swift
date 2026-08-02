import SwiftUI

// The awake-hours background: a quiet piece of space. Seeded, so the sky is
// identical on every launch — stars don't reshuffle. The night session screen
// deliberately does NOT use this: sessions are pure black, all business.
struct SpaceBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.008, green: 0.008, blue: 0.016)

            // Nebula washes — barely-there color depth
            RadialGradient(colors: [Color(red: 0.20, green: 0.12, blue: 0.32).opacity(0.35), .clear],
                           center: .init(x: 0.75, y: 0.25), startRadius: 20, endRadius: 340)
            RadialGradient(colors: [Color(red: 0.08, green: 0.14, blue: 0.30).opacity(0.32), .clear],
                           center: .init(x: 0.18, y: 0.70), startRadius: 10, endRadius: 300)
            RadialGradient(colors: [Color(red: 0.30, green: 0.18, blue: 0.10).opacity(0.18), .clear],
                           center: .init(x: 0.55, y: 0.95), startRadius: 10, endRadius: 260)

            Canvas { context, size in
                var rng = SplitMix64(seed: 20260802)

                func star(x: CGFloat, y: CGFloat, r: CGFloat, tint: Color, opacity: CGFloat) {
                    if r > 1.3 {
                        // halo for the brightest stars
                        let halo = Path(ellipseIn: CGRect(x: x - r * 3, y: y - r * 3, width: r * 6, height: r * 6))
                        context.fill(halo, with: .color(tint.opacity(opacity * 0.12)))
                    }
                    let dot = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    context.fill(dot, with: .color(tint.opacity(opacity)))
                }

                func pickTint() -> Color {
                    let roll = rng.unit()
                    if roll < 0.78 { return Color(red: 0.95, green: 0.93, blue: 0.87) }   // cream-white
                    if roll < 0.92 { return Color(red: 0.75, green: 0.82, blue: 0.98) }   // blue-white
                    return Color(red: 0.95, green: 0.78, blue: 0.55)                       // amber
                }

                // Galaxy band: dense faint stars along a diagonal
                for _ in 0..<300 {
                    let t = rng.unit()
                    let alongX = t * size.width
                    let bandCenterY = size.height * (0.15 + 0.55 * t)   // diagonal
                    let spread = rng.gaussian() * size.width * 0.07
                    star(x: alongX, y: bandCenterY + spread,
                         r: 0.4 + rng.unit() * 0.7,
                         tint: pickTint(),
                         opacity: 0.10 + rng.unit() * 0.30)
                }

                // Field stars
                for _ in 0..<190 {
                    let brightness = rng.unit()
                    star(x: rng.unit() * size.width,
                         y: rng.unit() * size.height,
                         r: 0.4 + pow(brightness, 3) * 1.7,
                         tint: pickTint(),
                         opacity: 0.20 + brightness * 0.65)
                }

                // Star clusters
                for _ in 0..<4 {
                    let cx = rng.unit() * size.width
                    let cy = rng.unit() * size.height
                    let clusterR = size.width * (0.04 + rng.unit() * 0.05)
                    for _ in 0..<28 {
                        star(x: cx + rng.gaussian() * clusterR,
                             y: cy + rng.gaussian() * clusterR,
                             r: 0.35 + rng.unit() * 0.8,
                             tint: pickTint(),
                             opacity: 0.15 + rng.unit() * 0.45)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

// Seedable RNG (SystemRandomNumberGenerator can't be seeded)
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> CGFloat {
        CGFloat(next() >> 11) / CGFloat(1 << 53)
    }

    // Box-Muller, one value at a time
    mutating func gaussian() -> CGFloat {
        let u1 = max(unit(), 1e-9)
        let u2 = unit()
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}

#Preview {
    SpaceBackground()
}
