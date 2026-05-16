import SwiftUI
import MapKit
import CoreLocation

struct MapScreen: View {
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var workspace: WorkspaceStore
    @StateObject private var tracker = LocationTracker.shared

    @State private var zipPolys: [(code: String, polygon: MKPolygon)] = []
    @State private var nbPolys: [(key: NeighborhoodKey, polygon: MKPolygon)] = []
    @State private var spanDeg: Double = 0.8

    @State private var droppedCoord: CLLocationCoordinate2D?
    @State private var droppedAddress: String?
    @State private var sheetOpen = false
    @State private var selectedHome: HomeRow?
    @State private var selectedNeighborhood: NeighborhoodRow?
    @State private var selectedZip: ZipRow?

    private var showNeighborhoods: Bool { true }

    var body: some View {
        ZStack(alignment: .top) {
            HomeMapView(
                zipPolys: zipPolys,
                nbPolys: nbPolys,
                homes: repo.homes,
                tempPin: droppedCoord,
                zipStatus: { code in
                    repo.zips.first(where: { $0.code == code })?.status ?? .unvisited
                },
                nbStatus: { key in
                    guard let z = repo.zips.first(where: { $0.code == key.zip }) else { return .unvisited }
                    return repo.neighborhoods.first(where: {
                        $0.zip_id == z.id && normalize($0.name) == normalize(key.name)
                    })?.status ?? .unvisited
                },
                currentZip: tracker.currentZipCode,
                currentNb: tracker.currentNeighborhoodKey,
                showNeighborhoods: showNeighborhoods,
                onLongPress: { coord in droppedAt(coord) },
                onSelectHome: { selectedHome = $0 },
                onSelectZip: { code in openZip(code) },
                onSelectNeighborhood: { key in openNeighborhood(key) },
                onSpanChange: { spanDeg = $0 }
            )
            .ignoresSafeArea()

            topBanner
                .padding(.horizontal)
                .padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $sheetOpen, onDismiss: { droppedCoord = nil; droppedAddress = nil }) {
            HomeFormView(
                prefilledCoord: droppedCoord,
                prefilledAddress: droppedAddress
            )
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(item: $selectedHome) { HomeDetailScreen(home: $0) }
        .sheet(item: $selectedNeighborhood) { row in
            NavigationStack { NeighborhoodDetailScreen(neighborhood: row) }
        }
        .sheet(item: $selectedZip) { row in
            NavigationStack { ZipDetailScreen(zip: row) }
        }
        .task { await loadPolygons() }
        .onAppear { tracker.start() }
    }

    private func droppedAt(_ coord: CLLocationCoordinate2D) {
        // 1) Pin appears on the map immediately at the press location.
        droppedCoord = coord
        droppedAddress = nil
        // 2) Reverse-geocode that exact coordinate (not GPS), then open the sheet
        //    with the address already populated.
        Task {
            let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            if let place = try? await CLGeocoder().reverseGeocodeLocation(loc).first {
                let parts = [place.subThoroughfare, place.thoroughfare, place.locality,
                             place.administrativeArea, place.postalCode].compactMap { $0 }
                droppedAddress = parts.joined(separator: " ")
            }
            sheetOpen = true
        }
    }

    @ViewBuilder
    private var topBanner: some View {
        if let key = tracker.currentNeighborhoodKey {
            bannerRow(icon: "mappin.and.ellipse",
                      title: key.name, subtitle: "ZIP \(key.zip)",
                      action: { openNeighborhood(key) })
        } else if let zip = tracker.currentZipCode {
            let city = repo.zips.first(where: { $0.code == zip })?.city ?? ""
            bannerRow(icon: "location.fill",
                      title: "ZIP \(zip)", subtitle: city,
                      action: nil)
        } else {
            EmptyView()
        }
    }

    private func bannerRow(icon: String, title: String, subtitle: String, action: (() -> Void)?) -> some View {
        HStack {
            Image(systemName: icon)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.subheadline.bold())
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if action != nil { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.thinMaterial, in: .rect(cornerRadius: 12))
        .shadow(radius: 4)
        .onTapGesture { action?() }
    }

    private func openNeighborhood(_ key: NeighborhoodKey) {
        guard let zipRow = repo.zips.first(where: { $0.code == key.zip }) else {
            openZip(key.zip); return
        }
        if let nb = repo.neighborhoods.first(where: {
            $0.zip_id == zipRow.id && normalize($0.name) == normalize(key.name)
        }) {
            selectedNeighborhood = nb
            return
        }
        // No existing row for this polygon's name — create one so the user
        // can mark its status and have the polygon recolor immediately.
        Task {
            guard let ws = workspace.current,
                  let nb = await repo.upsertNeighborhood(workspace: ws, zip: zipRow, name: key.name)
            else { return }
            selectedNeighborhood = nb
        }
    }

    private func openZip(_ code: String) {
        guard let z = repo.zips.first(where: { $0.code == code }) else { return }
        selectedZip = z
    }

    private func normalize(_ s: String) -> String {
        s.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }

    private func loadPolygons() async {
        if zipPolys.isEmpty {
            zipPolys = parsePolygons(resource: "zips") { feature in
                stringProp("zip", from: feature)
            }
        }
        if nbPolys.isEmpty {
            nbPolys = parsePolygons(resource: "neighborhoods") { feature in
                NeighborhoodKey(
                    name: stringProp("name", from: feature),
                    zip: stringProp("zip", from: feature)
                )
            }
        }
        tracker.setZipPolygons(zipPolys.map { ($0.code, $0.polygon) })
        tracker.setNeighborhoodPolygons(nbPolys.map { ($0.key, $0.polygon) })
    }

    private func parsePolygons<T>(resource: String, key: (MKGeoJSONFeature) -> T) -> [(T, MKPolygon)] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "geojson"),
              let data = try? Data(contentsOf: url),
              let objs = try? MKGeoJSONDecoder().decode(data) else { return [] }
        var out: [(T, MKPolygon)] = []
        for obj in objs {
            guard let f = obj as? MKGeoJSONFeature else { continue }
            let tag = key(f)
            for geom in f.geometry {
                if let poly = geom as? MKPolygon { out.append((tag, poly)) }
                else if let multi = geom as? MKMultiPolygon {
                    for poly in multi.polygons { out.append((tag, poly)) }
                }
            }
        }
        return out
    }

    private func stringProp(_ k: String, from feature: MKGeoJSONFeature) -> String {
        guard let p = feature.properties,
              let json = try? JSONSerialization.jsonObject(with: p) as? [String: Any]
        else { return "" }
        return (json[k] as? String) ?? ""
    }
}
