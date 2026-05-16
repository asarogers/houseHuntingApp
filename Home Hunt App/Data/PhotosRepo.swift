import Foundation
import Combine
import Supabase
import UIKit

@MainActor
final class PhotosRepo: ObservableObject {
    @Published var byHome: [UUID: [HomePhotoRow]] = [:]
    @Published var signedURLs: [UUID: URL] = [:]

    private let bucket = "home-photos"

    func load(for home: HomeRow) async {
        do {
            let rows: [HomePhotoRow] = try await Supa.client.from("home_photos")
                .select().eq("home_id", value: home.id)
                .order("created_at", ascending: false)
                .execute().value
            byHome[home.id] = rows
            for r in rows { await sign(r) }
        } catch {
            print("photos load failed:", error)
        }
    }

    func upload(image: UIImage, home: HomeRow, workspaceID: UUID, caption: String?) async {
        guard let data = image.jpegData(compressionQuality: 0.82) else { return }
        let path = "\(workspaceID.uuidString)/\(home.id.uuidString)/\(UUID().uuidString).jpg"
        do {
            _ = try await Supa.client.storage.from(bucket).upload(
                path,
                data: data,
                options: FileOptions(contentType: "image/jpeg", upsert: false)
            )
            struct Insert: Codable {
                let home_id: UUID; let workspace_id: UUID
                let storage_path: String; let caption: String?
            }
            let row: HomePhotoRow = try await Supa.client.from("home_photos")
                .insert(Insert(home_id: home.id, workspace_id: workspaceID,
                               storage_path: path, caption: caption))
                .select().single().execute().value
            byHome[home.id, default: []].insert(row, at: 0)
            await sign(row)
        } catch {
            print("photo upload failed:", error)
        }
    }

    func delete(_ photo: HomePhotoRow) async {
        do {
            _ = try await Supa.client.storage.from(bucket).remove(paths: [photo.storage_path])
            _ = try await Supa.client.from("home_photos").delete().eq("id", value: photo.id).execute()
            byHome[photo.home_id]?.removeAll { $0.id == photo.id }
            signedURLs[photo.id] = nil
        } catch {
            print("photo delete failed:", error)
        }
    }

    private func sign(_ photo: HomePhotoRow) async {
        do {
            let url = try await Supa.client.storage.from(bucket)
                .createSignedURL(path: photo.storage_path, expiresIn: 60 * 60 * 6)
            signedURLs[photo.id] = url
        } catch {
            print("sign failed:", error)
        }
    }
}
