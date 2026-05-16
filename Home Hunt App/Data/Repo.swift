import Foundation
import Combine
import Supabase

@MainActor
final class Repo: ObservableObject {
    @Published var zips: [ZipRow] = []
    @Published var neighborhoods: [NeighborhoodRow] = []
    @Published var homes: [HomeRow] = []
    @Published var loading = false

    private var realtimeTask: Task<Void, Never>?

    func load(workspace: Workspace) async {
        loading = true; defer { loading = false }
        do {
            async let z: [ZipRow] = Supa.client.from("zips")
                .select().eq("workspace_id", value: workspace.id)
                .order("code").execute().value
            async let n: [NeighborhoodRow] = Supa.client.from("neighborhoods")
                .select().eq("workspace_id", value: workspace.id)
                .order("name").execute().value
            async let h: [HomeRow] = Supa.client.from("homes")
                .select().eq("workspace_id", value: workspace.id)
                .order("created_at", ascending: false).execute().value
            zips = try await z
            neighborhoods = try await n
            homes = try await h
        } catch {
            print("load failed:", error)
        }
        subscribe(workspace: workspace)
    }

    private func subscribe(workspace: Workspace) {
        realtimeTask?.cancel()
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            let channel = Supa.client.channel("ws-\(workspace.id.uuidString)")
            let homeChanges = channel.postgresChange(
                AnyAction.self, schema: "public", table: "homes"
            )
            let zipChanges = channel.postgresChange(
                AnyAction.self, schema: "public", table: "zips"
            )
            let nbChanges = channel.postgresChange(
                AnyAction.self, schema: "public", table: "neighborhoods"
            )
            await channel.subscribe()
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await _ in homeChanges { await self.reloadHomes(workspace: workspace) } }
                group.addTask { for await _ in zipChanges  { await self.reloadZips(workspace: workspace) } }
                group.addTask { for await _ in nbChanges   { await self.reloadNeighborhoods(workspace: workspace) } }
            }
        }
    }

    private func reloadHomes(workspace: Workspace) async {
        if let h: [HomeRow] = try? await Supa.client.from("homes")
            .select().eq("workspace_id", value: workspace.id)
            .order("created_at", ascending: false).execute().value {
            self.homes = h
        }
    }
    private func reloadZips(workspace: Workspace) async {
        if let z: [ZipRow] = try? await Supa.client.from("zips")
            .select().eq("workspace_id", value: workspace.id)
            .order("code").execute().value {
            self.zips = z
        }
    }
    private func reloadNeighborhoods(workspace: Workspace) async {
        if let n: [NeighborhoodRow] = try? await Supa.client.from("neighborhoods")
            .select().eq("workspace_id", value: workspace.id)
            .order("name").execute().value {
            self.neighborhoods = n
        }
    }

    func upsertNeighborhood(workspace: Workspace, zip: ZipRow, name: String) async -> NeighborhoodRow? {
        // If we already have a local row with this (zip_id, name), return it.
        if let existing = neighborhoods.first(where: {
            $0.zip_id == zip.id && normalize($0.name) == normalize(name)
        }) {
            return existing
        }
        struct Insert: Codable { let workspace_id: UUID; let zip_id: UUID; let name: String }
        do {
            let row: NeighborhoodRow = try await Supa.client.from("neighborhoods")
                .upsert(Insert(workspace_id: workspace.id, zip_id: zip.id, name: name),
                        onConflict: "zip_id,name")
                .select()
                .single()
                .execute()
                .value
            if !neighborhoods.contains(where: { $0.id == row.id }) {
                neighborhoods.append(row)
            }
            return row
        } catch {
            print("upsertNeighborhood failed:", error)
            return nil
        }
    }

    private func normalize(_ s: String) -> String {
        s.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }

    func setZipStatus(_ zip: ZipRow, status: NeighborhoodStatus) async {
        // Optimistic local update so the map repaints immediately.
        let prev = zips.first(where: { $0.id == zip.id })?.status
        if let idx = zips.firstIndex(where: { $0.id == zip.id }) {
            zips[idx].status = status
        }
        struct Patch: Codable { let status: String }
        do {
            _ = try await Supa.client.from("zips")
                .update(Patch(status: status.rawValue))
                .eq("id", value: zip.id).execute()
        } catch {
            print("setZipStatus failed, reverting:", error)
            if let prev, let idx = zips.firstIndex(where: { $0.id == zip.id }) {
                zips[idx].status = prev
            }
        }
    }

    func setNeighborhoodStatus(_ n: NeighborhoodRow, status: NeighborhoodStatus) async {
        let prev = neighborhoods.first(where: { $0.id == n.id })?.status
        if let idx = neighborhoods.firstIndex(where: { $0.id == n.id }) {
            neighborhoods[idx].status = status
        }
        struct Patch: Codable { let status: String }
        do {
            _ = try await Supa.client.from("neighborhoods")
                .update(Patch(status: status.rawValue))
                .eq("id", value: n.id).execute()
        } catch {
            print("setNeighborhoodStatus failed, reverting:", error)
            if let prev, let idx = neighborhoods.firstIndex(where: { $0.id == n.id }) {
                neighborhoods[idx].status = prev
            }
        }
    }

    @discardableResult
    func addHomeReturningID(workspace: Workspace, address: String, lat: Double?, lng: Double?,
                            price: Int?, notes: String?, zipId: UUID?, neighborhoodId: UUID?,
                            listingURL: String?) async -> UUID? {
        struct Insert: Codable {
            let workspace_id: UUID
            let neighborhood_id: UUID?
            let zip_id: UUID?
            let address: String
            let lat: Double?
            let lng: Double?
            let price: Int?
            let listing_url: String?
            let notes: String?
            let created_by: UUID?
        }
        let uid = Supa.client.auth.currentUser?.id
        let row = Insert(workspace_id: workspace.id, neighborhood_id: neighborhoodId,
                         zip_id: zipId, address: address, lat: lat, lng: lng,
                         price: price, listing_url: listingURL, notes: notes, created_by: uid)
        do {
            let inserted: HomeRow = try await Supa.client.from("homes")
                .insert(row).select().single().execute().value
            return inserted.id
        } catch {
            print("add home failed:", error)
            return nil
        }
    }

    func addHome(workspace: Workspace, address: String, lat: Double?, lng: Double?,
                 price: Int?, notes: String?, zipId: UUID?, neighborhoodId: UUID?,
                 listingURL: String?) async {
        struct Insert: Codable {
            let workspace_id: UUID
            let neighborhood_id: UUID?
            let zip_id: UUID?
            let address: String
            let lat: Double?
            let lng: Double?
            let price: Int?
            let listing_url: String?
            let notes: String?
            let created_by: UUID?
        }
        let uid = Supa.client.auth.currentUser?.id
        let row = Insert(workspace_id: workspace.id, neighborhood_id: neighborhoodId,
                         zip_id: zipId, address: address, lat: lat, lng: lng,
                         price: price, listing_url: listingURL, notes: notes, created_by: uid)
        _ = try? await Supa.client.from("homes").insert(row).execute()
    }

    func setHomeStatus(_ home: HomeRow, status: HomeStatus) async {
        let prev = homes.first(where: { $0.id == home.id })?.status
        if let idx = homes.firstIndex(where: { $0.id == home.id }) {
            homes[idx].status = status
        }
        struct Patch: Codable { let status: String }
        do {
            _ = try await Supa.client.from("homes")
                .update(Patch(status: status.rawValue))
                .eq("id", value: home.id).execute()
        } catch {
            print("setHomeStatus failed, reverting:", error)
            if let prev, let idx = homes.firstIndex(where: { $0.id == home.id }) {
                homes[idx].status = prev
            }
        }
    }
}
