import SwiftUI

struct YOLOLogo: View {
    var height: CGFloat = 80

    var body: some View {
        // SVG viewBox is 986 x 592, so aspect ratio is ~1.66
        let aspectRatio: CGFloat = 986 / 592
        let width = height * aspectRatio

        ZStack {
            // Y
            YOLOLogoPath.letterY
                .fill(Color.white)

            // First O
            YOLOLogoPath.letterO1
                .fill(Color.white, style: FillStyle(eoFill: true))

            // L
            YOLOLogoPath.letterL
                .fill(Color.white)

            // Second O
            YOLOLogoPath.letterO2
                .fill(Color.white, style: FillStyle(eoFill: true))
        }
        .frame(width: width, height: height)
    }
}

enum YOLOLogoPath {
    // Original viewBox: 0 0 986 592
    static let letterY: Path = {
        var path = Path()
        // Y path from SVG
        path.move(to: CGPoint(x: 74.13/986, y: 485.01/592))
        path.addCurve(
            to: CGPoint(x: 125.72/986, y: 468.21/592),
            control1: CGPoint(x: 84.35/986, y: 484.61/592),
            control2: CGPoint(x: 113.12/986, y: 482.02/592)
        )
        // Simplified - using the actual SVG image is better
        return path
    }()

    static let letterO1: Path = Path()
    static let letterL: Path = Path()
    static let letterO2: Path = Path()
}

// Use the actual SVG as an image instead of path reconstruction
struct YOLOLogoImage: View {
    var height: CGFloat = 80

    var body: some View {
        Image("yolo-logo-white")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
            .foregroundColor(.white)
    }
}

#Preview {
    ZStack {
        SkyBackground(colors: NightSky.colors(NightSky.dusk))
        VStack {
            YOLOLogoImage(height: 100)
        }
    }
}
