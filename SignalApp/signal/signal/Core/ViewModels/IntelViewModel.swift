import SwiftUI
import Observation

@MainActor
@Observable
final class IntelViewModel {
    var stats: Stats? = nil
    var feeds: [Feed] = []
    var discovered: [DiscoveredSource] = []
    var tasteProfile: TasteProfile? = nil
    var profileInteractionCount: Int = 0
    var profileError: String? = nil
    var isLoading = false
    var error: String? = nil

    private let api = APIService.shared

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        async let statsTask      = api.fetchStats()
        async let feedsTask      = api.fetchFeeds()
        async let discoveredTask = api.fetchDiscovered()
        async let profileTask    = api.fetchProfile()

        do {
            let (s, f, d) = try await (statsTask, feedsTask, discoveredTask)
            stats = s
            feeds = f
            discovered = d
        } catch {
            self.error = error.localizedDescription
        }

        // Profile fetch is independent — 404 means not ready yet (not an error)
        do {
            let profile = try await profileTask
            tasteProfile = profile
            profileInteractionCount = profile.interactionCount ?? 0
        } catch APIError.httpError(404) {
            // Not enough interactions yet — normal state
            tasteProfile = nil
            if let stats = stats {
                profileInteractionCount = stats.interactionCount
            }
        } catch {
            profileError = error.localizedDescription
        }

        isLoading = false
    }

    func approveSource(_ source: DiscoveredSource) {
        Task {
            try? await api.updateDiscovered(id: source.id, status: "added")
            await load()
        }
    }

    func rejectSource(_ source: DiscoveredSource) {
        Task {
            try? await api.updateDiscovered(id: source.id, status: "rejected")
            discovered.removeAll { $0.id == source.id }
        }
    }

    func deleteFeed(_ feed: Feed) {
        Task {
            try? await api.deleteFeed(id: feed.id)
            feeds.removeAll { $0.id == feed.id }
        }
    }

    var pendingDiscovered: [DiscoveredSource] {
        discovered.filter { $0.status == "pending" }
    }
}
