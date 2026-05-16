import SwiftUI

struct RootView: View {
    @EnvironmentObject var workspace: WorkspaceStore
    @StateObject private var repo = Repo()

    var body: some View {
        TabView {
            MapScreen()
                .tabItem { Label("Map", systemImage: "map") }
            ZipListScreen()
                .tabItem { Label("ZIPs", systemImage: "list.bullet") }
            HomesListScreen()
                .tabItem { Label("Homes", systemImage: "house") }
            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .environmentObject(repo)
        .task(id: workspace.current?.id) {
            if let ws = workspace.current { await repo.load(workspace: ws) }
        }
    }
}
