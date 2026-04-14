import SwiftUI
import BackgroundTasks

@MainActor
@Observable
final class AppEnvironment {
    static let shared = AppEnvironment()

    var lastRefreshedAt: Date? = nil

    private init() {}

    // MARK: - Background refresh registration
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.signal.feed-refresh",
            using: nil
        ) { task in
            Task { @MainActor in
                await AppEnvironment.shared.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
            }
        }
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.signal.feed-refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30 min minimum
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleBackgroundRefresh(task: BGAppRefreshTask) async {
        scheduleBackgroundRefresh() // re-schedule immediately

        task.expirationHandler = { task.setTaskCompleted(success: false) }

        // Trigger backend refresh
        APIService.shared.triggerRefresh()
        lastRefreshedAt = Date()
        task.setTaskCompleted(success: true)
    }
}
