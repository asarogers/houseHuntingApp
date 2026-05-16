import Foundation

enum NeighborhoodStatus: String, Codable, CaseIterable, Identifiable {
    case unvisited, none_for_sale, explored, revisit
    var id: String { rawValue }
    var label: String {
        switch self {
        case .unvisited: return "Unvisited"
        case .none_for_sale: return "Nothing for sale"
        case .explored: return "Explored"
        case .revisit: return "Revisit"
        }
    }
}

enum HomeStatus: String, Codable, CaseIterable, Identifiable {
    case interested, passed, visiting, offer, lost, bought
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct Workspace: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let invite_code: String
    let created_by: UUID
}

struct ZipRow: Codable, Identifiable, Hashable {
    let id: UUID
    let workspace_id: UUID
    let code: String
    let city: String
    var status: NeighborhoodStatus
    var notes: String?
}

struct NeighborhoodRow: Codable, Identifiable, Hashable {
    let id: UUID
    let workspace_id: UUID
    let zip_id: UUID
    let name: String
    var status: NeighborhoodStatus
    var notes: String?
}

struct HomeRow: Codable, Identifiable, Hashable {
    let id: UUID
    let workspace_id: UUID
    var neighborhood_id: UUID?
    var zip_id: UUID?
    var address: String
    var lat: Double?
    var lng: Double?
    var price: Int?
    var beds: Double?
    var baths: Double?
    var sqft: Int?
    var listing_url: String?
    var status: HomeStatus
    var notes: String?
}

struct HomePhotoRow: Codable, Identifiable, Hashable {
    let id: UUID
    let home_id: UUID
    let workspace_id: UUID
    let storage_path: String
    var caption: String?
}
