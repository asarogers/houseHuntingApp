import Foundation
import Combine
import CoreLocation
import MapKit

@MainActor
final class LocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationTracker()

    private let manager = CLLocationManager()
    @Published var location: CLLocationCoordinate2D?
    @Published var currentZipCode: String?
    @Published var currentNeighborhoodKey: NeighborhoodKey?

    private var zipPolygons: [(code: String, polygon: MKPolygon)] = []
    private var neighborhoodPolygons: [(key: NeighborhoodKey, polygon: MKPolygon)] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }
    func stop() { manager.stopUpdatingLocation() }

    func setZipPolygons(_ polys: [(String, MKPolygon)]) {
        self.zipPolygons = polys.map { (code: $0.0, polygon: $0.1) }
        recompute()
    }
    func setNeighborhoodPolygons(_ polys: [(NeighborhoodKey, MKPolygon)]) {
        self.neighborhoodPolygons = polys.map { (key: $0.0, polygon: $0.1) }
        recompute()
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let l = locs.last else { return }
        location = l.coordinate
        recompute()
    }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        print("loc tracker failed:", error)
    }

    private func recompute() {
        guard let loc = location else { return }
        let point = MKMapPoint(loc)
        currentZipCode = polygonContaining(point: point, in: zipPolygons.map { ($0.code, $0.polygon) })
        currentNeighborhoodKey = polygonContaining(point: point, in: neighborhoodPolygons.map { ($0.key, $0.polygon) })
    }

    private func polygonContaining<T>(point: MKMapPoint, in polys: [(T, MKPolygon)]) -> T? {
        for (tag, poly) in polys {
            let renderer = MKPolygonRenderer(polygon: poly)
            let viewPoint = renderer.point(for: point)
            if renderer.path?.contains(viewPoint) == true { return tag }
        }
        return nil
    }

    func zipCode(for coord: CLLocationCoordinate2D) -> String? {
        polygonContaining(point: MKMapPoint(coord),
                          in: zipPolygons.map { ($0.code, $0.polygon) })
    }
    func neighborhoodKey(for coord: CLLocationCoordinate2D) -> NeighborhoodKey? {
        polygonContaining(point: MKMapPoint(coord),
                          in: neighborhoodPolygons.map { ($0.key, $0.polygon) })
    }
}

struct NeighborhoodKey: Hashable, Equatable {
    let name: String
    let zip: String
}
