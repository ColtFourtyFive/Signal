import SwiftUI
import Observation

@MainActor
@Observable
final class ArticleViewModel {
    private(set) var article: Article
    private var readingStartedAt: Date? = nil
    private var timer: Timer? = nil
    private var posted30s = false
    private var posted60s = false

    private let api = APIService.shared

    init(article: Article) {
        self.article = article
    }

    // MARK: - Reading timer

    func startReading() {
        readingStartedAt = Date()
        posted30s = false
        posted60s = false

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    func stopReading() {
        guard let startedAt = readingStartedAt else { return }
        timer?.invalidate()
        timer = nil

        let elapsed = Date().timeIntervalSince(startedAt)

        if elapsed < 5 && !posted30s {
            // Closed fast
            api.interact(articleId: article.id, type: "closed_fast")
        }
        readingStartedAt = nil
    }

    private func tick() {
        guard let startedAt = readingStartedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)

        if elapsed >= 30 && !posted30s {
            posted30s = true
            api.interact(articleId: article.id, type: "read_30s")
        }
        if elapsed >= 60 && !posted60s {
            posted60s = true
            api.interact(articleId: article.id, type: "read_60s")
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: - Actions

    func toggleSave() {
        article.isSaved.toggle()
        api.interact(articleId: article.id, type: article.isSaved ? "saved" : "dismissed")
        if article.isSaved {
            HapticService.notification(.success)
        }
    }

    func share() -> URL? {
        api.interact(articleId: article.id, type: "shared")
        return URL(string: article.url)
    }
}
