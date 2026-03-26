import Foundation
import UserNotifications

class NotificationService {
    static let shared = NotificationService()

    private var lastWarningNotified: Date? = nil
    private var lastCriticalNotified: Date? = nil

    private let cooldownInterval: TimeInterval = 3600 // 1 hour between repeat notifications

    /// UNUserNotificationCenter requires a valid app bundle with a bundle identifier.
    /// When running via `swift run` (bare executable), there is no bundle.
    private var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    private init() {}

    // MARK: - Authorization

    func requestAuthorization() {
        guard isAvailable else {
            print("NotificationService: skipping — no app bundle (run via .app bundle for notifications)")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("NotificationService: authorization error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Threshold Checking

    func checkThresholds(usage: UsageSnapshot, settings: AppSettings) {
        guard isAvailable, settings.notificationsEnabled else { return }

        let utilization = Double(usage.sevenDayUtilization)

        if utilization >= settings.criticalThreshold {
            if shouldSendNotification(lastSent: lastCriticalNotified) {
                sendNotification(
                    title: "Claude Usage Critical",
                    body: "You've used \(usage.sevenDayUtilization)% of your 7-day limit.",
                    isCritical: true
                )
                lastCriticalNotified = Date()
            }
        } else if utilization >= settings.warningThreshold {
            if shouldSendNotification(lastSent: lastWarningNotified) {
                sendNotification(
                    title: "Claude Usage Warning",
                    body: "You've used \(usage.sevenDayUtilization)% of your 7-day limit.",
                    isCritical: false
                )
                lastWarningNotified = Date()
            }
        }
    }

    // MARK: - Private Helpers

    private func shouldSendNotification(lastSent: Date?) -> Bool {
        guard let lastSent else { return true }
        return Date().timeIntervalSince(lastSent) >= cooldownInterval
    }

    private func sendNotification(title: String, body: String, isCritical: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let identifier = isCritical ? "claude-usage-critical" : "claude-usage-warning"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("NotificationService: failed to deliver notification: \(error.localizedDescription)")
            }
        }
    }
}
