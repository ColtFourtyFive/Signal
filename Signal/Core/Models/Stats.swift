import Foundation

struct Stats: Codable {
    let articlestoday: Int
    let breakingToday: Int
    let byCategory: [String: Int]
    let tasteStrength: Int
    let interactionCount: Int
    let sourcesActive: Int
    let sourcesDiscoveredThisWeek: Int
    let lastRefresh: Date?
    let topSourcesToday: [TopSource]
    let newSourcesAdded: Int

    struct TopSource: Codable, Identifiable {
        var id: String { name }
        let name: String
        let count: Int
    }

    var tasteLabel: String {
        switch interactionCount {
        case 0..<10:  return "Keep reading to personalize your feed"
        case 10..<30: return "Your feed is learning"
        default:      return "Your feed is well calibrated"
        }
    }

    var topCategories: [(name: String, count: Int)] {
        byCategory
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { (name: $0.key.categoryDisplayName, count: $0.value) }
    }
}
