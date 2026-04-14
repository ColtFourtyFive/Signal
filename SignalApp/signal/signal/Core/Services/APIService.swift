import Foundation

private let kAPIBaseURL = "https://signal-production-9b0e.up.railway.app"

enum APIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case httpError(Int)
    case decodingError(Error)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:            return "Invalid URL"
        case .networkError(let e):   return "Network error: \(e.localizedDescription)"
        case .httpError(let code):   return "HTTP \(code)"
        case .decodingError(let e):  return "Decode error: \(e.localizedDescription)"
        case .serverError(let msg):  return msg
        }
    }
}

final class APIService {
    static let shared = APIService()
    private init() {}

    private let session = URLSession.shared

    // MARK: - Decoder (handles Supabase fractional-second timestamps)
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]

        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = iso.date(from: str) { return date }
            if let date = isoPlain.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(str)"
            )
        }
        return d
    }()

    // MARK: - Generic request
    private func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        guard let url = URL(string: kAPIBaseURL + path) else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30

        if let body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            // Try to extract server error message
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = json["error"] as? String {
                throw APIError.serverError(msg)
            }
            throw APIError.httpError(http.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // Fire-and-forget — for interactions (non-blocking)
    private func fireAndForget(_ path: String, method: String = "POST", body: [String: Any]? = nil) {
        Task {
            _ = try? await request(path, method: method, body: body) as EmptyResponse
        }
    }

    // MARK: - Feed

    struct FeedResponse: Decodable {
        let articles: [Article]
        let page: Int
        let limit: Int
    }

    struct ArticlesResponse: Decodable {
        let articles: [Article]
    }

    struct ArticleResponse: Decodable {
        let article: Article
    }

    func fetchFeed(page: Int = 1, category: String? = nil, unreadOnly: Bool = false) async throws -> FeedResponse {
        var path = "/api/articles/feed?page=\(page)&limit=20"
        if let cat = category, cat != "all" { path += "&category=\(cat)" }
        if unreadOnly { path += "&unread_only=true" }
        return try await request(path)
    }

    func fetchBreaking() async throws -> [Article] {
        let response: ArticlesResponse = try await request("/api/articles/feed/breaking")
        return response.articles
    }

    func fetchArticle(id: String) async throws -> Article {
        let response: ArticleResponse = try await request("/api/articles/\(id)")
        return response.article
    }

    func interact(articleId: String, type: String) {
        fireAndForget("/api/articles/\(articleId)/interact", method: "PATCH", body: ["type": type])
    }

    func fetchSaved() async throws -> [Article] {
        let response: ArticlesResponse = try await request("/api/articles/saved/list")
        return response.articles
    }

    func search(query: String) async throws -> [Article] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let response: ArticlesResponse = try await request("/api/articles/search/query?q=\(encoded)")
        return response.articles
    }

    // MARK: - Feeds

    struct FeedsResponse: Decodable {
        let feeds: [Feed]
    }

    struct DiscoveredResponse: Decodable {
        let sources: [DiscoveredSource]
    }

    func fetchFeeds() async throws -> [Feed] {
        let response: FeedsResponse = try await request("/api/feeds")
        return response.feeds
    }

    func addFeed(url: String) async throws {
        let _: EmptyResponse = try await request("/api/feeds/add", method: "POST", body: ["url": url])
    }

    func deleteFeed(id: String) async throws {
        let _: EmptyResponse = try await request("/api/feeds/\(id)", method: "DELETE")
    }

    func fetchDiscovered() async throws -> [DiscoveredSource] {
        let response: DiscoveredResponse = try await request("/api/feeds/discovered")
        return response.sources
    }

    func updateDiscovered(id: String, status: String) async throws {
        let _: EmptyResponse = try await request("/api/feeds/discovered/\(id)", method: "PATCH", body: ["status": status])
    }

    // MARK: - Intel

    func fetchStats() async throws -> Stats {
        return try await request("/api/stats")
    }

    func triggerRefresh() {
        fireAndForget("/api/refresh", method: "POST")
    }

    func fetchProfile() async throws -> TasteProfile {
        return try await request("/api/profile")
    }

    func registerPushToken(_ token: String) async throws {
        let _: EmptyResponse = try await request("/api/push/register", method: "POST", body: ["token": token])
    }

    // MARK: - Onboarding

    struct CalibrationArticlesResponse: Decodable {
        let articles: [Article]
    }

    func fetchCalibrationArticles() async throws -> [Article] {
        let response: CalibrationArticlesResponse = try await request("/api/onboarding/articles")
        return response.articles
    }

    func submitCalibration(_ swipes: [(articleId: String, liked: Bool)]) async throws {
        let body = swipes.map { ["articleId": $0.articleId, "liked": $0.liked] as [String: Any] }
        let _: EmptyResponse = try await request("/api/onboarding/calibrate", method: "POST", body: ["swipes": body])
    }
}

// Dummy decodable for fire-and-forget responses
private struct EmptyResponse: Decodable {}
