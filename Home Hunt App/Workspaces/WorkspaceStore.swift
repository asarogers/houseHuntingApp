import Foundation
import Combine
import Supabase

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var current: Workspace?
    @Published var loading = false
    @Published var error: String?
    @Published var pendingInviteCode: String?

    /// Call when a homehunt://join?code=XYZ link opens the app.
    func acceptInvite(code: String) async {
        pendingInviteCode = code
        if Supa.client.auth.currentUser != nil {
            await join(code: code)
        }
        // If not signed in yet, the code stays pending and gets applied
        // after sign-in via consumePendingInvite().
    }

    func consumePendingInvite() async {
        guard let code = pendingInviteCode, current == nil else { return }
        await join(code: code)
        pendingInviteCode = nil
    }

    func loadCurrent() async {
        loading = true; defer { loading = false }
        do {
            let rows: [Workspace] = try await Supa.client
                .from("workspaces")
                .select()
                .limit(1)
                .execute()
                .value
            current = rows.first
        } catch {
            self.error = error.localizedDescription
        }
    }

    func create(name: String) async {
        loading = true; defer { loading = false }
        do {
            struct Params: Encodable { let name: String }
            let ws: Workspace = try await Supa.client
                .rpc("create_workspace", params: Params(name: name))
                .execute()
                .value
            current = ws
            await Seeder.seedIfNeeded(workspace: ws)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func join(code: String) async {
        loading = true; defer { loading = false }
        do {
            struct Params: Codable { let code: String }
            _ = try await Supa.client
                .rpc("join_workspace", params: Params(code: code))
                .execute()
            pendingInviteCode = nil
            await loadCurrent()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
