import Foundation

struct TasteProfile: Codable {
    let id: String
    let profileText: String
    let primaryInterests: [String: Double]
    let topSources: [TopSource]
    let keyEntities: KeyEntities
    let antiInterests: [String]
    let basedOnInteractions: Int
    let confidenceScore: Double
    let lastUpdated: Date
    let createdAt: Date

    // Injected from the API response (not in DB row)
    let interactionCount: Int?

    struct TopSource: Codable {
        let name: String
        let engagement: Double
    }

    struct KeyEntities: Codable {
        let models: [String]
        let benchmarks: [String]
        let techniques: [String]
        let organizations: [String]
    }

    // MARK: - Computed helpers

    var confidencePercent: Int { Int((confidenceScore * 100).rounded()) }

    var sortedInterests: [(key: String, value: Double)] {
        primaryInterests.sorted { $0.value > $1.value }
    }

    var topInterests: [(key: String, value: Double)] {
        Array(sortedInterests.prefix(5))
    }
}
