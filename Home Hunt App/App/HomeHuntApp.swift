import SwiftUI
import Supabase
import GoogleSignIn

@main
struct HomeHuntApp: App {
    @StateObject private var auth = AuthStore()
    @StateObject private var workspace = WorkspaceStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.session == nil {
                    AuthView()
                } else if workspace.current == nil {
                    WorkspaceGateView()
                } else {
                    RootView()
                }
            }
            .environmentObject(auth)
            .environmentObject(workspace)
            .task { await auth.bootstrap() }
            .task(id: auth.session?.user.id) {
                guard auth.session != nil else { return }
                await workspace.loadCurrent()
                await workspace.consumePendingInvite()
            }
             
            .onOpenURL { url in
                if url.scheme == "homehunt" {
                    handleInviteURL(url)
                } else {
                    GIDSignIn.sharedInstance.handle(url)
                }
            }
        }
    }

    private func handleInviteURL(_ url: URL) {
        guard url.host == "join" else { return }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else { return }
        Task { await workspace.acceptInvite(code: code) }
    }
}
