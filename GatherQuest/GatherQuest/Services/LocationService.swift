import Foundation
import Combine
import CoreLocation

/// CoreLocation wrapper. distanceFilter = 10 m; the repository adds a 15 s
/// minimum interval on top, per the write-throttling requirement.
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    @Published var current: CLLocation?
    var onUpdate: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // 10 m so CL callbacks arrive promptly; Firestore writes are still
        // throttled to one per 15 s in GroupRepository (per requirement).
        manager.distanceFilter = 10
        manager.allowsBackgroundLocationUpdates = false
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        requestPermission()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        current = loc
        onUpdate?(loc)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Non-fatal for the hackathon build.
        print("Location error: \(error.localizedDescription)")
    }
}
