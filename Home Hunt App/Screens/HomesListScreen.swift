import SwiftUI

struct HomesListScreen: View {
    @EnvironmentObject var repo: Repo
    @State private var statusFilter: HomeStatus?
    @State private var showingAdd = false

    private var filtered: [HomeRow] {
        guard let s = statusFilter else { return repo.homes }
        return repo.homes.filter { $0.status == s }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Status", selection: $statusFilter) {
                        Text("All").tag(HomeStatus?.none)
                        ForEach(HomeStatus.allCases) { Text($0.label).tag(HomeStatus?.some($0)) }
                    }
                    .pickerStyle(.menu)
                }

                if filtered.isEmpty {
                    Text("No homes yet. Tap + to add one.").foregroundStyle(.secondary)
                }

                ForEach(filtered) { h in
                    NavigationLink(value: h) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(h.address).font(.subheadline)
                            HStack {
                                Text(h.status.label).font(.caption)
                                if let p = h.price { Text("· $\(p)").font(.caption.monospaced()) }
                            }.foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Homes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus.circle.fill") }
                }
            }
            .sheet(isPresented: $showingAdd) { HomeFormView() }
            .navigationDestination(for: HomeRow.self) { HomeDetailScreen(home: $0) }
        }
    }
}
