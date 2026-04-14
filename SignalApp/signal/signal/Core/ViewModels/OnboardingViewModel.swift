import SwiftUI
import Observation

enum OnboardingScreen {
    case welcome, calibration, generating
}

@MainActor
@Observable
final class OnboardingViewModel {
    var currentScreen: OnboardingScreen = .welcome
    var calibrationArticles: [Article] = []
    var currentIndex: Int = 0
    var swipeResults: [(articleId: String, liked: Bool)] = []
    var isLoadingArticles = false
    var loadError: String? = nil

    var progress: Double {
        guard !calibrationArticles.isEmpty else { return 0 }
        return Double(currentIndex) / Double(calibrationArticles.count)
    }

    var currentArticle: Article? {
        guard currentIndex < calibrationArticles.count else { return nil }
        return calibrationArticles[currentIndex]
    }

    private let api = APIService.shared

    func loadCalibrationArticles() async {
        isLoadingArticles = true
        loadError = nil
        do {
            calibrationArticles = try await api.fetchCalibrationArticles()
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingArticles = false
    }

    func swipe(liked: Bool) {
        guard let article = currentArticle else { return }
        HapticService.impact(.medium)
        swipeResults.append((articleId: article.id, liked: liked))

        if currentIndex + 1 >= calibrationArticles.count {
            Task { await submitCalibration() }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                currentIndex += 1
            }
        }
    }

    func submitCalibration() async {
        currentScreen = .generating
        do {
            try await api.submitCalibration(swipeResults)
        } catch {
            // Profile generation failed silently — user can still use the app
            print("[onboarding] Calibration submission failed: \(error.localizedDescription)")
        }
        UserDefaults.standard.set(true, forKey: "onboarding_complete")
    }
}
