import SwiftUI
import Combine
import PhotosUI
import CoreLocation
import MapKit

@MainActor
final class LocationOnce: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var coord: CLLocationCoordinate2D?
    @Published var address: String?

    override init() {
        super.init()
        manager.delegate = self
    }
    func request() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }
    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let l = locs.last else { return }
        coord = l.coordinate
        Task {
            if let place = try? await CLGeocoder().reverseGeocodeLocation(l).first {
                let parts = [place.subThoroughfare, place.thoroughfare, place.locality,
                             place.administrativeArea, place.postalCode].compactMap { $0 }
                await MainActor.run { self.address = parts.joined(separator: " ") }
            }
        }
    }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        print("loc failed:", error)
    }
}

struct HomeFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var workspace: WorkspaceStore
    @StateObject private var photos = PhotosRepo()

    let prefilledCoord: CLLocationCoordinate2D?
    let prefilledAddress: String?

    @State private var address = ""
    @State private var price = ""
    @State private var listingURL = ""
    @State private var notes = ""
    @State private var zipId: UUID?
    @State private var neighborhoodId: UUID?
    @State private var lat: Double?
    @State private var lng: Double?

    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingImages: [UIImage] = []
    @State private var showCamera = false
    @State private var saving = false

    init(prefilledCoord: CLLocationCoordinate2D? = nil,
         prefilledAddress: String? = nil) {
        self.prefilledCoord = prefilledCoord
        self.prefilledAddress = prefilledAddress
    }

    var body: some View {
        NavigationStack {
            Form {
                if let lat = lat, let lng = lng {
                    Section {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                        ))) {
                            Marker("Dropped pin",
                                   coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng))
                        }
                        .frame(height: 160)
                        .listRowInsets(EdgeInsets())
                    }
                }

                Section("Where") {
                    TextField("Address", text: $address, axis: .vertical)
                        .lineLimit(1...3)

                    Picker("ZIP", selection: $zipId) {
                        Text("—").tag(UUID?.none)
                        ForEach(repo.zips) { Text("\($0.code) · \($0.city)").tag(UUID?.some($0.id)) }
                    }
                    if let zid = zipId {
                        let opts = repo.neighborhoods.filter { $0.zip_id == zid }
                        if !opts.isEmpty {
                            Picker("Neighborhood", selection: $neighborhoodId) {
                                Text("—").tag(UUID?.none)
                                ForEach(opts) { Text($0.name).tag(UUID?.some($0.id)) }
                            }
                        }
                    }
                }

                Section("Details") {
                    TextField("Price (USD)", text: $price).keyboardType(.numberPad)
                    TextField("Listing URL", text: $listingURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...6)
                }

                Section("Photos") {
                    HStack(spacing: 12) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Take photo", systemImage: "camera.fill")
                        }
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("From library", systemImage: "photo.on.rectangle")
                        }
                    }
                    if !pendingImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(pendingImages.enumerated()), id: \.offset) { i, img in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: img).resizable().scaledToFill()
                                            .frame(width: 100, height: 100)
                                            .clipShape(.rect(cornerRadius: 10))
                                        Button {
                                            pendingImages.remove(at: i)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.white, .black.opacity(0.6))
                                                .font(.title3)
                                        }
                                        .padding(4)
                                    }
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }
                }
            }
            .navigationTitle("New home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(address.isEmpty || saving)
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { img in
                    pendingImages.append(img)
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        pendingImages.append(img)
                    }
                    pickerItem = nil
                }
            }
            .onAppear { applyPrefill() }
        }
    }

    private func applyPrefill() {
        if let c = prefilledCoord {
            lat = c.latitude; lng = c.longitude
            assignZipAndNeighborhood(for: c)
        }
        if let a = prefilledAddress, address.isEmpty { address = a }
    }

    private func assignZipAndNeighborhood(for coord: CLLocationCoordinate2D) {
        let tracker = LocationTracker.shared
        let mp = MKMapPoint(coord)
        // We don't have direct access to polygons here, so derive via current zip/nb
        // Use LocationTracker's current values if user is near; otherwise leave unset.
        // Better: ask the tracker to do a one-off lookup against its polygons.
        // For now, the LocationTracker exposes currentZipCode / currentNeighborhoodKey via GPS;
        // for a dropped pin we look the coord up against the same polygons.
        _ = mp
        if let z = tracker.zipCode(for: coord),
           let zipRow = repo.zips.first(where: { $0.code == z }) {
            zipId = zipRow.id
            if let key = tracker.neighborhoodKey(for: coord),
               let n = repo.neighborhoods.first(where: {
                   $0.zip_id == zipRow.id && normalized($0.name) == normalized(key.name)
               }) {
                neighborhoodId = n.id
            }
        }
    }

    private func normalized(_ s: String) -> String {
        s.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }

    private func save() async {
        guard let ws = workspace.current else { return }
        saving = true
        defer { saving = false }
        let newId = await repo.addHomeReturningID(
            workspace: ws,
            address: address.trimmingCharacters(in: .whitespacesAndNewlines),
            lat: lat, lng: lng,
            price: Int(price),
            notes: notes.isEmpty ? nil : notes,
            zipId: zipId,
            neighborhoodId: neighborhoodId,
            listingURL: listingURL.isEmpty ? nil : listingURL
        )
        if let id = newId, !pendingImages.isEmpty {
            // Build a minimal HomeRow to satisfy the photo upload API
            let placeholder = HomeRow(
                id: id, workspace_id: ws.id, neighborhood_id: neighborhoodId, zip_id: zipId,
                address: address, lat: lat, lng: lng, price: Int(price),
                beds: nil, baths: nil, sqft: nil,
                listing_url: listingURL.isEmpty ? nil : listingURL,
                status: .interested,
                notes: notes.isEmpty ? nil : notes
            )
            for img in pendingImages {
                await photos.upload(image: img, home: placeholder, workspaceID: ws.id, caption: nil)
            }
        }
        dismiss()
    }
}
