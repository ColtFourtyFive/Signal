import SwiftUI
import UIKit
import UserNotifications

// MARK: - AppDelegate for push token handling

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { try? await APIService.shared.registerPushToken(tokenString) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[push] Failed to register: \(error.localizedDescription)")
    }
}

// MARK: - App entry point

@main
struct SignalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appEnv = AppEnvironment.shared

    init() {
        configureAppearance()
        AppEnvironment.shared.registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .environment(appEnv)
                .task { await requestPushPermission() }
        }
    }

    private func requestPushPermission() async {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        if granted == true {
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    private func configureAppearance() {
        // Tab bar
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(DesignSystem.Colors.background)
        tabAppearance.stackedLayoutAppearance.selected.iconColor = UIColor(DesignSystem.Colors.accent)
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor(DesignSystem.Colors.accent)
        ]
        tabAppearance.stackedLayoutAppearance.normal.iconColor = UIColor(DesignSystem.Colors.textTertiary)
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor(DesignSystem.Colors.textTertiary)
        ]
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        // Navigation bar
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(DesignSystem.Colors.background)
        navAppearance.shadowColor = UIColor(DesignSystem.Colors.border)
        navAppearance.titleTextAttributes = [
            .foregroundColor: UIColor(DesignSystem.Colors.textPrimary)
        ]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            FeedView()
                .tabItem {
                    Label("Feed", systemImage: "bolt.fill")
                }

            SavedView()
                .tabItem {
                    Label("Saved", systemImage: "bookmark.fill")
                }

            IntelView()
                .tabItem {
                    Label("Intel", systemImage: "chart.bar.fill")
                }
        }
        .signalBackground()
    }
}
