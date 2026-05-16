import SwiftUI

struct ZipListScreen: View {
    @EnvironmentObject var repo: Repo
    @State private var search = ""

    private var grouped: [(city: String, zips: [ZipRow])] {
        let filtered = repo.zips.filter {
            search.isEmpty || $0.code.contains(search)
              || $0.city.localizedCaseInsensitiveContains(search)
        }
        let byCity = Dictionary(grouping: filtered, by: { $0.city })
        return byCity.map { (city: $0.key, zips: $0.value.sorted { $0.code < $1.code }) }
                     .sorted { $0.city < $1.city }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.city) { group in
                    Section(group.city) {
                        ForEach(group.zips) { z in
                            NavigationLink(value: z) {
                                ZipRowView(zip: z, homeCount: repo.homes.filter { $0.zip_id == z.id }.count)
                            }
                        }
                    }
                }
            }
            .navigationTitle("ZIP codes")
            .searchable(text: $search, prompt: "ZIP or city")
            .navigationDestination(for: ZipRow.self) { ZipDetailScreen(zip: $0) }
        }
    }
}

private struct ZipRowView: View {
    let zip: ZipRow
    let homeCount: Int
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(zip.code).font(.headline.monospaced())
                Text(zip.status.label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if homeCount > 0 {
                Text("\(homeCount)").font(.caption.monospaced())
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: .capsule)
            }
            Circle().fill(color(for: zip.status)).frame(width: 10, height: 10)
        }
    }
    private func color(for s: NeighborhoodStatus) -> Color {
        switch s {
        case .unvisited: return .blue
        case .none_for_sale: return .gray
        case .explored: return .green
        case .revisit: return .orange
        }
    }
}
