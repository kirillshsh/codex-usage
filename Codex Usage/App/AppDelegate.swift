import Cocoa
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var menuBarManager: MenuBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable window restoration for menu bar app
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")

        // Set app icon early for Stage Manager and windows
        if let appIcon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = appIcon
        }

        // Hide dock icon (menu bar app only)
        NSApp.setActivationPolicy(.accessory)

        // Load profiles before creating menu bar manager
        ProfileManager.shared.loadProfiles()

        // Initialize update manager to enable automatic update checks
        _ = UpdateManager.shared

        // Request notification permissions
        requestNotificationPermissions()

        // Initialize menu bar immediately (Codex-only flow, no setup wizard)
        menuBarManager = MenuBarManager()
        menuBarManager?.setup()

    }

    private func requestNotificationPermissions() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            // Silently request permissions
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup
        menuBarManager?.cleanup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running even if all windows are closed
        return false
    }

    func application(_ application: NSApplication, willEncodeRestorableState coder: NSCoder) {
        // Prevent window restoration state from being saved
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        // Disable state restoration for menu bar app
        return false
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notifications even when app is in foreground (menu bar apps are always foreground)
        completionHandler([.banner, .sound])
    }
}
