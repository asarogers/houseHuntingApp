import Foundation
import Supabase

enum Seeder {
    struct CityFile: Codable {
        struct City: Codable { let city: String; let zipCodes: [String] }
        let cities: [City]
    }
    struct NeighborhoodsFile: Codable {
        struct City: Codable { let city: String; let zips: [Zip] }
        struct Zip: Codable { let zipcode: String; let neighborhoods: [String]? }
        let cities: [City]
    }

    static func seedIfNeeded(workspace: Workspace) async {
        do {
            let existing: [ZipRow] = try await Supa.client
                .from("zips")
                .select()
                .eq("workspace_id", value: workspace.id)
                .limit(1)
                .execute()
                .value
            guard existing.isEmpty else { return }
        } catch {
            print("seed precheck failed:", error)
            return
        }

        guard
            let cityURL = Bundle.main.url(forResource: "city", withExtension: "json"),
            let cityData = try? Data(contentsOf: cityURL),
            let cities = try? JSONDecoder().decode(CityFile.self, from: cityData)
        else {
            print("city.json missing from bundle"); return
        }

        struct ZipInsert: Codable { let workspace_id: UUID; let code: String; let city: String }
        var zipInserts: [ZipInsert] = []
        for c in cities.cities {
            for z in c.zipCodes {
                zipInserts.append(.init(workspace_id: workspace.id, code: z, city: c.city))
            }
        }
        do {
            let inserted: [ZipRow] = try await Supa.client
                .from("zips")
                .insert(zipInserts)
                .select()
                .execute()
                .value

            let zipIdByCode = Dictionary(uniqueKeysWithValues: inserted.map { ($0.code, $0.id) })

            if let nURL = Bundle.main.url(forResource: "neighborhoods", withExtension: "json"),
               let nData = try? Data(contentsOf: nURL),
               let n = try? JSONDecoder().decode(NeighborhoodsFile.self, from: nData) {
                struct NbInsert: Codable {
                    let workspace_id: UUID; let zip_id: UUID; let name: String
                }
                var inserts: [NbInsert] = []
                for c in n.cities {
                    for z in c.zips {
                        guard let zid = zipIdByCode[z.zipcode], let names = z.neighborhoods else { continue }
                        for name in Set(names) {
                            inserts.append(.init(workspace_id: workspace.id, zip_id: zid, name: name))
                        }
                    }
                }
                if !inserts.isEmpty {
                    _ = try await Supa.client.from("neighborhoods").insert(inserts).execute()
                }
            }
        } catch {
            print("seed failed:", error)
        }
    }
}
