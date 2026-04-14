import Foundation

struct CacheService {
    private static let feedKey = "signal_feed_cache"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func saveFeed(_ articles: [Article]) {
        guard let data = try? encoder.encode(articles) else { return }
        UserDefaults.standard.set(data, forKey: feedKey)
    }

    static func loadFeed() -> [Article] {
        guard let data = UserDefaults.standard.data(forKey: feedKey),
              let articles = try? decoder.decode([Article].self, from: data)
        else { return [] }
        return articles
    }
}
