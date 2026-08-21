import Foundation
import CoreLocation
import Combine
import os

// The real moon: altitude and azimuth right now, from the observer's location.
// Low-precision Meeus series (the suncalc formulation, ~1° accuracy) — entirely
// on-device, no network. Location is a one-shot coarse fix, cached so the moon
// still renders offline or before the first fix of the night.
@MainActor
final class MoonTracker: NSObject, ObservableObject {
    struct MoonPosition {
        let altitude: Double  // radians, 0 = on the horizon
        let azimuth: Double   // radians, measured from south, west positive
        let hourAngle: Double // radians, 0 = culmination (highest point), west positive
        let horizonCos: Double // cos of the rise/set hour angle: where the horizon cuts the diurnal circle
    }

    @Published private(set) var position: MoonPosition?
    @Published private(set) var sunPosition: MoonPosition?

    private let manager = CLLocationManager()
    private var coordinate: CLLocationCoordinate2D? {
        didSet { refresh() }
    }

    private static let latKey = "moonTrackerLat"
    private static let lonKey = "moonTrackerLon"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced

        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.latKey) != nil {
            coordinate = CLLocationCoordinate2D(
                latitude: defaults.double(forKey: Self.latKey),
                longitude: defaults.double(forKey: Self.lonKey)
            )
        }
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break  // No location, no moon — never nag
        }
        refresh()
    }

    func refresh(at date: Date = Date()) {
        guard let coordinate else {
            position = nil
            sunPosition = nil
            return
        }
        position = Self.moonPosition(date: date,
                                     latitude: coordinate.latitude,
                                     longitude: coordinate.longitude)
        sunPosition = Self.sunPosition(date: date,
                                       latitude: coordinate.latitude,
                                       longitude: coordinate.longitude)
    }

    // MARK: - Astronomy

    private static let rad = Double.pi / 180
    private static let obliquity = 23.4397 * rad

    static func moonPosition(date: Date, latitude: Double, longitude: Double) -> MoonPosition {
        let d = date.timeIntervalSince1970 / 86_400 - 10_957.5  // days since J2000

        // Ecliptic coordinates
        let L = rad * (218.316 + 13.176396 * d)   // mean longitude
        let M = rad * (134.963 + 13.064993 * d)   // mean anomaly
        let F = rad * (93.272 + 13.229350 * d)    // mean distance

        let lon = L + rad * 6.289 * sin(M)
        let lat = rad * 5.128 * sin(F)

        // Equatorial coordinates
        let ra = atan2(sin(lon) * cos(obliquity) - tan(lat) * sin(obliquity), cos(lon))
        let dec = asin(sin(lat) * cos(obliquity) + cos(lat) * sin(obliquity) * sin(lon))

        // Local hour angle
        let lw = rad * -longitude
        let phi = rad * latitude
        let siderealTime = rad * (280.16 + 360.9856235 * d) - lw
        let h = siderealTime - ra

        let altitude = asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(h))
        let azimuth = atan2(sin(h), cos(h) * sin(phi) - tan(dec) * cos(phi))

        // Wrap the hour angle to (-π, π]: 0 at culmination, ±π at the low point
        let wrapped = atan2(sin(h), cos(h))
        // Standard rise/set condition: cos H₀ = -tan φ · tan δ. Clamped values
        // mean the moon is circumpolar (never sets / never rises) tonight.
        let horizonCos = min(max(-tan(phi) * tan(dec), -1), 1)

        return MoonPosition(altitude: altitude, azimuth: azimuth,
                            hourAngle: wrapped, horizonCos: horizonCos)
    }

    // The sun, same formulation (suncalc's low-precision series)
    static func sunPosition(date: Date, latitude: Double, longitude: Double) -> MoonPosition {
        let d = date.timeIntervalSince1970 / 86_400 - 10_957.5

        // Ecliptic longitude from mean anomaly + equation of center + perihelion
        let m = rad * (357.5291 + 0.98560028 * d)
        let c = rad * (1.9148 * sin(m) + 0.02 * sin(2 * m) + 0.0003 * sin(3 * m))
        let p = rad * 102.9372
        let lon = m + c + p + .pi

        let ra = atan2(sin(lon) * cos(obliquity), cos(lon))
        let dec = asin(sin(lon) * sin(obliquity))

        let lw = rad * -longitude
        let phi = rad * latitude
        let siderealTime = rad * (280.16 + 360.9856235 * d) - lw
        let h = siderealTime - ra

        let altitude = asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(h))
        let azimuth = atan2(sin(h), cos(h) * sin(phi) - tan(dec) * cos(phi))
        let wrapped = atan2(sin(h), cos(h))
        let horizonCos = min(max(-tan(phi) * tan(dec), -1), 1)

        return MoonPosition(altitude: altitude, azimuth: azimuth,
                            hourAngle: wrapped, horizonCos: horizonCos)
    }
}

extension MoonTracker: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            let defaults = UserDefaults.standard
            defaults.set(location.coordinate.latitude, forKey: Self.latKey)
            defaults.set(location.coordinate.longitude, forKey: Self.lonKey)
            self.coordinate = location.coordinate
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Logger.session.error("🌙 Location fix failed: \(String(describing: error.localizedDescription), privacy: .public)")
    }
}
