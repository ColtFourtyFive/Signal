import Foundation

struct Feed: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let url: String
    let category: String?
    let isActive: Bool
    let isAutoDiscovered: Bool
    let lastFetchedAt: Date?
    let articleCount: Int
    let avgScore: Double
    let isBroken: Bool
    let isLowQuality: Bool
    let createdAt: Date

    var categoryDisplay: String { category?.categoryDisplayName ?? "GENERAL" }
    var healthStatus: HealthStatus {
        switch avgScore {
        case 7...: return .good
        case 5..<7: return .fair
        default:   return .poor
        }
    }

    enum HealthStatus {
        case good, fair, poor
    }
}

struct DiscoveredSource: Identifiable, Codable {
    let id: String
    let name: String?
    let url: String?
    let rssUrl: String?
    let avgScore: Double?
    let discoveryReason: String?
    let status: String
    let discoveredAt: Date
}
