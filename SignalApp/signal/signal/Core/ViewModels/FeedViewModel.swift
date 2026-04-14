import SwiftUI
import Observation

@MainActor
@Observable
final class FeedViewModel {
    var articles: [Article] = []
    var filteredArticles: [Article] = []
    var breakingArticles: [Article] = []
    var isLoading = false
    var isRefreshing = false
    var isOffline = false
    var hasMore = true
    var error: String? = nil
    var selectedCategory: String? = nil
    var searchQuery = ""

    private var currentPage = 1
    private var isLoadingMore = false

    private let api = APIService.shared

    // MARK: - Load

    func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        currentPage = 1
        hasMore = true
        isOffline = false

        do {
            async let feedTask = api.fetchFeed(page: 1, category: selectedCategory)
            async let breakingTask = api.fetchBreaking()
            let (response, breaking) = try await (feedTask, breakingTask)
            articles = response.articles
            filteredArticles = response.articles
            breakingArticles = breaking
            hasMore = response.articles.count == 20
            CacheService.saveFeed(response.articles)
        } catch {
            self.error = error.localizedDescription
            let cached = CacheService.loadFeed()
            if !cached.isEmpty {
                articles = cached
                filteredArticles = cached
                isOffline = true
            }
        }

        isLoading = false
    }

    func loadMore() async {
        guard !isLoadingMore, hasMore, !articles.isEmpty, searchQuery.isEmpty else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1

        do {
            let response = try await api.fetchFeed(page: nextPage, category: selectedCategory)
            if response.articles.isEmpty {
                hasMore = false
            } else {
                let existingIds = Set(articles.map(\.id))
                let newArticles = response.articles.filter { !existingIds.contains($0.id) }
                articles.append(contentsOf: newArticles)
                filteredArticles = articles
                currentPage = nextPage
                hasMore = response.articles.count == 20
            }
        } catch {
            // Silently fail on pagination errors
        }

        isLoadingMore = false
    }

    // MARK: - Search (debounced via .task(id:) in the view)

    func search(_ query: String) async {
        if query.isEmpty {
            filteredArticles = articles
            return
        }
        do {
            let results = try await api.search(query: query)
            filteredArticles = results
        } catch {
            // Fall back to local filter on network error
            let q = query.lowercased()
            filteredArticles = articles.filter {
                $0.title.lowercased().contains(q) ||
                ($0.content?.lowercased().contains(q) ?? false)
            }
        }
    }

    func refresh() async {
        isRefreshing = true
        api.triggerRefresh()
        // Wait briefly then reload
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await loadInitial()
        isRefreshing = false
    }

    // MARK: - Category filter

    func selectCategory(_ category: String?) {
        guard selectedCategory != category else { return }
        selectedCategory = category
        searchQuery = ""
        Task { await loadInitial() }
    }

    // MARK: - Interactions

    func save(_ article: Article) {
        api.interact(articleId: article.id, type: "saved")
        updateArticle(id: article.id) { $0.isSaved = true }
    }

    func dismiss(_ article: Article) {
        api.interact(articleId: article.id, type: "dismissed")
        withAnimation(DesignSystem.Animation.spring) {
            articles.removeAll { $0.id == article.id }
            filteredArticles.removeAll { $0.id == article.id }
        }
    }

    func markRead(_ article: Article) {
        updateArticle(id: article.id) { $0.isRead = true }
    }

    private func updateArticle(id: String, mutation: (inout Article) -> Void) {
        if let idx = articles.firstIndex(where: { $0.id == id }) {
            mutation(&articles[idx])
        }
    }
}
