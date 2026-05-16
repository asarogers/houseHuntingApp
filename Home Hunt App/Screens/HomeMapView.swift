import SwiftUI
import MapKit
import UIKit

final class HomeAnnotation: NSObject, MKAnnotation {
    let home: HomeRow
    init(home: HomeRow) { self.home = home }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: home.lat ?? 0, longitude: home.lng ?? 0)
    }
    var title: String? { home.address }
    var subtitle: String? { home.status.label }
}

final class TempPinAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    init(coord: CLLocationCoordinate2D) { self.coordinate = coord }
    var title: String? { "Dropped pin" }
}

struct HomeMapView: UIViewRepresentable {
    var zipPolys: [(code: String, polygon: MKPolygon)]
    var nbPolys: [(key: NeighborhoodKey, polygon: MKPolygon)]
    var homes: [HomeRow]
    var tempPin: CLLocationCoordinate2D?

    var zipStatus: (String) -> NeighborhoodStatus
    var nbStatus: (NeighborhoodKey) -> NeighborhoodStatus
    var currentZip: String?
    var currentNb: NeighborhoodKey?

    var showNeighborhoods: Bool

    var onLongPress: (CLLocationCoordinate2D) -> Void
    var onSelectHome: (HomeRow) -> Void
    var onSelectZip: (String) -> Void
    var onSelectNeighborhood: (NeighborhoodKey) -> Void
    var onSpanChange: (Double) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mv = MKMapView(frame: .zero)
        mv.showsUserLocation = true
        mv.delegate = context.coordinator
        let gr = UILongPressGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.longPress(_:)))
        gr.minimumPressDuration = 0.55
        mv.addGestureRecognizer(gr)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.tap(_:)))
        tap.numberOfTapsRequired = 1
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        mv.addGestureRecognizer(tap)
        // Wait for MK's gestures to exist, then require our single-tap to wait for
        // MK's double-tap-to-zoom to fail. That way double-tap still zooms, and a
        // single tap (after the failure delay) opens the polygon detail.
        DispatchQueue.main.async {
            for recognizer in mv.gestureRecognizers ?? [] {
                if let t = recognizer as? UITapGestureRecognizer,
                   t.numberOfTapsRequired == 2,
                   t !== tap {
                    tap.require(toFail: t)
                }
            }
        }
        mv.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.45, longitude: -122.15),
            span: MKCoordinateSpan(latitudeDelta: 0.8, longitudeDelta: 0.8)
        ), animated: false)
        return mv
    }

    func updateUIView(_ mv: MKMapView, context: Context) {
        let coord = context.coordinator
        coord.parent = self
        // Reconcile overlays based on the visible map rect (viewport culling).
        coord.reconcileVisibleOverlays(on: mv)
        coord.refreshOverlayColors(on: mv)

        // Home annotations
        let existing = mv.annotations.compactMap { $0 as? HomeAnnotation }
        let existingIDs = Set(existing.map { $0.home.id })
        let desiredHomes = homes.filter { $0.lat != nil && $0.lng != nil }
        let desiredIDs = Set(desiredHomes.map { $0.id })
        if existingIDs != desiredIDs {
            mv.removeAnnotations(existing)
            mv.addAnnotations(desiredHomes.map { HomeAnnotation(home: $0) })
        } else {
            for ann in existing {
                if let updated = desiredHomes.first(where: { $0.id == ann.home.id }) {
                    if let v = mv.view(for: ann) as? MKMarkerAnnotationView {
                        v.markerTintColor = Coordinator.uicolor(for: updated.status)
                        v.glyphImage = UIImage(systemName: Coordinator.glyph(for: updated.status))
                    }
                }
            }
        }

        // Temp pin
        let tempExisting = mv.annotations.compactMap { $0 as? TempPinAnnotation }
        if let pin = tempPin {
            if let first = tempExisting.first {
                first.coordinate = pin
                for extra in tempExisting.dropFirst() { mv.removeAnnotation(extra) }
            } else {
                mv.addAnnotation(TempPinAnnotation(coord: pin))
            }
        } else if !tempExisting.isEmpty {
            mv.removeAnnotations(tempExisting)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: HomeMapView
        // Tracks the last status we rendered for each polygon — when this
        // differs from the current desired status, we remove + re-add the
        // overlay so MapKit makes a fresh renderer with the new colors.
        private var appliedZipStatus: [ObjectIdentifier: NeighborhoodStatus] = [:]
        private var appliedNbStatus: [ObjectIdentifier: NeighborhoodStatus] = [:]
        private var appliedCurrentZip: String?
        private var appliedCurrentNb: NeighborhoodKey?

        init(parent: HomeMapView) { self.parent = parent }

        @objc func longPress(_ gr: UILongPressGestureRecognizer) {
            guard gr.state == .began, let mv = gr.view as? MKMapView else { return }
            let p = gr.location(in: mv)
            let coord = mv.convert(p, toCoordinateFrom: mv)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onLongPress(coord)
        }

        @objc func tap(_ gr: UITapGestureRecognizer) {
            guard gr.state == .ended, let mv = gr.view as? MKMapView else { return }
            // Skip if the tap hit an annotation view (let MK handle it via didSelect).
            let p = gr.location(in: mv)
            if let hit = mv.hitTest(p, with: nil), hit is MKAnnotationView || hit.superview is MKAnnotationView {
                return
            }
            let coord = mv.convert(p, toCoordinateFrom: mv)
            let mp = MKMapPoint(coord)
            // Prefer neighborhood (most specific)
            for entry in parent.nbPolys {
                if let r = mv.renderer(for: entry.polygon) as? MKPolygonRenderer {
                    let vp = r.point(for: mp)
                    if r.path?.contains(vp) == true {
                        parent.onSelectNeighborhood(entry.key)
                        return
                    }
                }
            }
            for entry in parent.zipPolys {
                if let r = mv.renderer(for: entry.polygon) as? MKPolygonRenderer {
                    let vp = r.point(for: mp)
                    if r.path?.contains(vp) == true {
                        parent.onSelectZip(entry.code)
                        return
                    }
                }
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        func mapView(_ mv: MKMapView, regionDidChangeAnimated _: Bool) {
            parent.onSpanChange(mv.region.span.latitudeDelta)
            reconcileVisibleOverlays(on: mv)
            refreshOverlayColors(on: mv)
        }

        func reconcileVisibleOverlays(on mv: MKMapView) {
            // Inflate the visible rect by ~20% so polygons just outside the edge
            // are already added (no pop-in as the user pans).
            let visible = mv.visibleMapRect
            let buffer = MKMapRect(
                x: visible.origin.x - visible.size.width * 0.1,
                y: visible.origin.y - visible.size.height * 0.1,
                width: visible.size.width * 1.2,
                height: visible.size.height * 1.2
            )

            var desiredZip: [ObjectIdentifier: MKPolygon] = [:]
            for entry in parent.zipPolys
                where entry.polygon.boundingMapRect.intersects(buffer) {
                desiredZip[ObjectIdentifier(entry.polygon)] = entry.polygon
            }
            var desiredNb: [ObjectIdentifier: MKPolygon] = [:]
            if parent.showNeighborhoods {
                for entry in parent.nbPolys
                    where entry.polygon.boundingMapRect.intersects(buffer) {
                    desiredNb[ObjectIdentifier(entry.polygon)] = entry.polygon
                }
            }

            let currentPolys = mv.overlays.compactMap { $0 as? MKPolygon }
            let currentIDs = Set(currentPolys.map { ObjectIdentifier($0) })
            let desiredIDs = Set(desiredZip.keys).union(desiredNb.keys)

            // Remove overlays that left the buffer
            let toRemove = currentPolys.filter { !desiredIDs.contains(ObjectIdentifier($0)) }
            if !toRemove.isEmpty { mv.removeOverlays(toRemove) }

            // Add overlays that entered the buffer (ZIP first so neighborhoods sit on top)
            let toAddZip = desiredZip.values.filter { !currentIDs.contains(ObjectIdentifier($0)) }
            let toAddNb = desiredNb.values.filter { !currentIDs.contains(ObjectIdentifier($0)) }
            if !toAddZip.isEmpty { mv.addOverlays(toAddZip) }
            if !toAddNb.isEmpty { mv.addOverlays(toAddNb) }
        }

        func mapView(_ mv: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let poly = overlay as? MKPolygon else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let r = MKPolygonRenderer(polygon: poly)
            apply(renderer: r, for: poly)
            return r
        }

        func mapView(_ mv: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let h = annotation as? HomeAnnotation {
                let id = "home"
                let view = (mv.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: h, reuseIdentifier: id)
                view.annotation = h
                view.markerTintColor = Coordinator.uicolor(for: h.home.status)
                view.glyphImage = UIImage(systemName: Coordinator.glyph(for: h.home.status))
                view.canShowCallout = true
                return view
            }
            if let t = annotation as? TempPinAnnotation {
                let id = "temp"
                let view = (mv.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: t, reuseIdentifier: id)
                view.annotation = t
                view.markerTintColor = .systemRed
                view.glyphImage = UIImage(systemName: "mappin.circle.fill")
                view.animatesWhenAdded = true
                return view
            }
            return nil
        }

        func mapView(_ mv: MKMapView, didSelect view: MKAnnotationView) {
            if let h = view.annotation as? HomeAnnotation {
                parent.onSelectHome(h.home)
                mv.deselectAnnotation(h, animated: false)
            }
        }

        func refreshOverlayColors(on mv: MKMapView) {
            // Find overlays whose desired status/highlight differs from what we
            // last rendered, and force-recreate them by remove + re-add.
            var stale: [MKPolygon] = []
            let visiblePolys = mv.overlays.compactMap { $0 as? MKPolygon }
            let visibleIDs = Set(visiblePolys.map { ObjectIdentifier($0) })

            for entry in parent.zipPolys {
                let id = ObjectIdentifier(entry.polygon)
                guard visibleIDs.contains(id) else { continue }
                let desired = parent.zipStatus(entry.code)
                let prev = appliedZipStatus[id]
                let nowCurrent = parent.currentZip == entry.code
                let wasCurrent = appliedCurrentZip == entry.code
                if prev != desired || nowCurrent != wasCurrent {
                    stale.append(entry.polygon)
                }
                appliedZipStatus[id] = desired
            }
            for entry in parent.nbPolys {
                let id = ObjectIdentifier(entry.polygon)
                guard visibleIDs.contains(id) else { continue }
                let desired = parent.nbStatus(entry.key)
                let prev = appliedNbStatus[id]
                let nowCurrent = parent.currentNb == entry.key
                let wasCurrent = appliedCurrentNb == entry.key
                if prev != desired || nowCurrent != wasCurrent {
                    stale.append(entry.polygon)
                }
                appliedNbStatus[id] = desired
            }
            appliedCurrentZip = parent.currentZip
            appliedCurrentNb = parent.currentNb

            guard !stale.isEmpty else { return }
            mv.removeOverlays(stale)
            mv.addOverlays(stale)
        }

        private static let currentColor = UIColor.systemBlue

        private func apply(renderer r: MKPolygonRenderer, for poly: MKPolygon) {
            for entry in parent.zipPolys where entry.polygon === poly {
                let status = parent.zipStatus(entry.code)
                let isCurrent = parent.currentZip == entry.code
                if isCurrent {
                    r.fillColor = Coordinator.currentColor.withAlphaComponent(0.22)
                    r.strokeColor = Coordinator.currentColor
                    r.lineWidth = 3
                } else {
                    let c = Coordinator.uicolor(for: status)
                    r.fillColor = c.withAlphaComponent(status == .unvisited ? 0.05 : 0.10)
                    r.strokeColor = c.withAlphaComponent(status == .unvisited ? 0.75 : 0.85)
                    r.lineWidth = status == .unvisited ? 1.2 : 1.4
                }
                return
            }
            for entry in parent.nbPolys where entry.polygon === poly {
                let status = parent.nbStatus(entry.key)
                let isCurrent = parent.currentNb == entry.key
                if isCurrent {
                    r.fillColor = Coordinator.currentColor.withAlphaComponent(0.45)
                    r.strokeColor = Coordinator.currentColor
                    r.lineWidth = 3.5
                } else {
                    let c = Coordinator.uicolor(for: status)
                    r.fillColor = c.withAlphaComponent(status == .unvisited ? 0.10 : 0.25)
                    r.strokeColor = c.withAlphaComponent(status == .unvisited ? 0.85 : 0.95)
                    r.lineWidth = status == .unvisited ? 1.4 : 1.6
                }
                return
            }
        }

        static func uicolor(for s: NeighborhoodStatus) -> UIColor {
            switch s {
            case .unvisited: return UIColor(white: 0.55, alpha: 1) // neutral mid-gray
            case .none_for_sale: return UIColor(red: 0.35, green: 0.35, blue: 0.40, alpha: 1) // darker slate
            case .explored: return .systemGreen
            case .revisit: return .systemOrange
            }
        }
        static func uicolor(for s: HomeStatus) -> UIColor {
            switch s {
            case .interested: return .systemYellow
            case .visiting: return .systemBlue
            case .offer: return .systemPurple
            case .bought: return .systemGreen
            case .passed, .lost: return .systemGray
            }
        }
        static func glyph(for s: HomeStatus) -> String {
            switch s {
            case .interested: return "star.fill"
            case .visiting: return "eye.fill"
            case .offer: return "hand.raised.fill"
            case .bought: return "checkmark.seal.fill"
            case .passed, .lost: return "xmark"
            }
        }
    }
}
