import SwiftUI
import Observation

enum TasteTunerScreen {
    case intro, tuning, generating, results
}

enum TasteTier: String {
    case mustRead    = "must_read"
    case interesting = "interesting"
    case skip        = "skip"
}

@MainActor
@Observable
final class TasteTunerViewModel {
    var currentScreen: TasteTunerScreen = .intro
    var articles: [Article] = []
    var currentIndex: Int = 0
    var ratings: [(articleId: String, tier: TasteTier)] = []
    var isLoading = false
    var loadError: String? = nil

    var progress: Double {
        guard !articles.isEmpty else { return 0 }
        return Double(currentIndex) / Double(articles.count)
    }

    var currentArticle: Article? {
        guard currentIndex < articles.count else { return nil }
        return articles[currentIndex]
    }

    var mustReadCount: Int { ratings.filter { $0.tier == .mustRead }.count }
    var interestingCount: Int { ratings.filter { $0.tier == .interesting }.count }
    var skipCount: Int { ratings.filter { $0.tier == .skip }.count }

    private let api = APIService.shared

    func loadArticles() async {
        isLoading = true
        loadError = nil
        do {
            articles = try await api.fetchTasteTunerArticles()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    func rate(_ tier: TasteTier) {
        guard let article = currentArticle else { return }

        switch tier {
        case .mustRead:    HapticService.impact(.heavy)
        case .interesting: HapticService.impact(.medium)
        case .skip:        HapticService.impact(.light)
        }

        ratings.append((articleId: article.id, tier: tier))

        if currentIndex + 1 >= articles.count {
            Task { await submit() }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                currentIndex += 1
            }
        }
    }

    func submit() async {
        currentScreen = .generating
        do {
            let payload = ratings.map { (articleId: $0.articleId, tier: $0.tier.rawValue) }
            try await api.submitTasteTunerRatings(payload)
        } catch {
            print("[taste-tuner] Submit failed: \(error.localizedDescription)")
        }
        UserDefaults.standard.set(true, forKey: "taste_tuner_completed")
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        currentScreen = .results
    }
}
