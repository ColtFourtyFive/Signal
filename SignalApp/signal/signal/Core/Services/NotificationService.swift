import UserNotifications
import UIKit

struct NotificationService {

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    static func scheduleBreakingAlert(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "● \(title)"
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func scheduleDiscoveryNotification(count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "New sources discovered"
        content.body = "Signal found \(count) sources matching your reading"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "discovery-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
