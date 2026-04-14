import Foundation

struct Article: Identifiable, Codable, Hashable {
    let id: String
    let feedId: String?
    let title: String
    let url: String
    let content: String?
    let publishedAt: Date?
    let score: Double?
    let scoreReason: String?
    let category: String?
    let isPrimarySource: Bool
    let keyEntities: [String]?
    let personalizationScore: Double?
    let profileMatchReason: String?
    let interactionCount: Int
    var isRead: Bool
    var isSaved: Bool
    var dismissed: Bool
    let createdAt: Date
    let feeds: FeedInfo?

    struct FeedInfo: Codable, Hashable {
        let name: String
        let category: String?
    }

    // MARK: - Computed helpers
    var feedName: String { feeds?.name ?? "Unknown" }
    var safeScore: Double { score ?? 0 }
    var entities: [String] { keyEntities ?? [] }
    var categoryName: String { category?.categoryDisplayName ?? "" }

    // MARK: - Hashable (by id)
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Article, rhs: Article) -> Bool { lhs.id == rhs.id }
}
