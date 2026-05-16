import SwiftUI

struct ZipDetailScreen: View {
    @EnvironmentObject var repo: Repo
    let zip: ZipRow

    private var live: ZipRow { repo.zips.first(where: { $0.id == zip.id }) ?? zip }
    private var neighborhoods: [NeighborhoodRow] {
        repo.neighborhoods.filter { $0.zip_id == zip.id }.sorted { $0.name < $1.name }
    }
    private var homes: [HomeRow] {
        repo.homes.filter { $0.zip_id == zip.id }
    }

    var body: some View {
        List {
            Section("Status") {
                Picker("ZIP status", selection: Binding(
                    get: { live.status },
                    set: { new in Task { await repo.setZipStatus(live, status: new) } }
                )) {
                    ForEach(NeighborhoodStatus.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if !neighborhoods.isEmpty {
                Section("Neighborhoods") {
                    ForEach(neighborhoods) { n in
                        NavigationLink(value: n) {
                            HStack {
                                Text(n.name)
                                Spacer()
                                Text(n.status.label).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Homes (\(homes.count))") {
                if homes.isEmpty {
                    Text("No homes logged here yet.").foregroundStyle(.secondary)
                }
                ForEach(homes) { h in
                    NavigationLink(value: h) {
                        VStack(alignment: .leading) {
                            Text(h.address).font(.subheadline)
                            HStack(spacing: 8) {
                                Text(h.status.label).font(.caption)
                                if let p = h.price { Text("$\(p)").font(.caption.monospaced()) }
                            }.foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("\(zip.code) · \(zip.city)")
        .navigationDestination(for: NeighborhoodRow.self) { NeighborhoodDetailScreen(neighborhood: $0) }
        .navigationDestination(for: HomeRow.self) { HomeDetailScreen(home: $0) }
    }
}

struct NeighborhoodDetailScreen: View {
    @EnvironmentObject var repo: Repo
    let neighborhood: NeighborhoodRow

    private var live: NeighborhoodRow {
        repo.neighborhoods.first(where: { $0.id == neighborhood.id }) ?? neighborhood
    }
    private var homes: [HomeRow] {
        repo.homes.filter { $0.neighborhood_id == neighborhood.id }
    }

    var body: some View {
        List {
            Section("Status") {
                Picker("Status", selection: Binding(
                    get: { live.status },
                    set: { new in Task { await repo.setNeighborhoodStatus(live, status: new) } }
                )) {
                    ForEach(NeighborhoodStatus.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Homes (\(homes.count))") {
                if homes.isEmpty {
                    Text("No homes logged here yet.").foregroundStyle(.secondary)
                }
                ForEach(homes) { h in
                    NavigationLink(value: h) {
                        VStack(alignment: .leading) {
                            Text(h.address).font(.subheadline)
                            Text(h.status.label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(neighborhood.name)
        .navigationDestination(for: HomeRow.self) { HomeDetailScreen(home: $0) }
    }
}
