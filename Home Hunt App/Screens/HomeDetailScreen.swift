import SwiftUI
import PhotosUI
import MapKit

struct HomeDetailScreen: View {
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var workspace: WorkspaceStore
    @StateObject private var photos = PhotosRepo()

    let home: HomeRow

    @State private var picker: PhotosPickerItem?
    @State private var notes: String = ""
    @State private var dirty = false

    private var photoRows: [HomePhotoRow] { photos.byHome[home.id] ?? [] }

    var body: some View {
        Form {
            if let lat = home.lat, let lng = home.lng {
                Section {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))) {
                        Marker(home.address, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng))
                    }
                    .frame(height: 180)
                    .listRowInsets(EdgeInsets())
                }
            }

            Section("Address") { Text(home.address) }

            Section("Status") {
                let live = repo.homes.first(where: { $0.id == home.id }) ?? home
                Picker("Status", selection: Binding(
                    get: { live.status },
                    set: { new in Task { await repo.setHomeStatus(live, status: new) } }
                )) {
                    ForEach(HomeStatus.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            }

            Section("Details") {
                if let p = home.price { Text("Price: $\(p)") }
                if let b = home.beds, let ba = home.baths {
                    Text("\(b, specifier: "%.1f") bd / \(ba, specifier: "%.1f") ba")
                }
                if let s = home.sqft { Text("\(s) sqft") }
                if let url = home.listing_url, let u = URL(string: url) {
                    Link("Open listing", destination: u)
                }
            }

            Section("Notes") {
                TextEditor(text: $notes).frame(minHeight: 80)
                    .onChange(of: notes) { _, _ in dirty = true }
            }

            Section("Photos") {
                PhotosPicker(selection: $picker, matching: .images) {
                    Label("Add photo", systemImage: "camera.fill")
                }
                if photoRows.isEmpty {
                    Text("No photos yet.").foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(photoRows) { p in
                                photoThumb(p)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            notes = home.notes ?? ""
            Task { await photos.load(for: home) }
        }
        .onChange(of: picker) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data),
                   let ws = workspace.current {
                    await photos.upload(image: img, home: home, workspaceID: ws.id, caption: nil)
                }
                picker = nil
            }
        }
    }

    @ViewBuilder
    private func photoThumb(_ p: HomePhotoRow) -> some View {
        if let url = photos.signedURLs[p.id] {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                        .frame(width: 110, height: 110).clipShape(.rect(cornerRadius: 10))
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await photos.delete(p) }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                default:
                    Rectangle().fill(.gray.opacity(0.2))
                        .frame(width: 110, height: 110).clipShape(.rect(cornerRadius: 10))
                }
            }
        } else {
            ProgressView().frame(width: 110, height: 110)
        }
    }
}
