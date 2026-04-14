import SwiftUI
import Observation

@MainActor
@Observable
final class SavedViewModel {
    var articles: [Article] = []
    var isLoading = false
    var error: String? = nil
    var selectedCategory: String? = nil

    private let api = APIService.shared

    var searchQuery = ""

    var filteredArticles: [Article] {
        var result = articles
        if let cat = selectedCategory, cat != "all" {
            result = result.filter { $0.category == cat }
        }
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(q) ||
                ($0.content?.lowercased().contains(q) ?? false)
            }
        }
        return result
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        do {
            articles = try await api.fetchSaved()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func unsave(_ article: Article) {
        api.interact(articleId: article.id, type: "dismissed")
        withAnimation(DesignSystem.Animation.spring) {
            articles.removeAll { $0.id == article.id }
        }
    }
}
