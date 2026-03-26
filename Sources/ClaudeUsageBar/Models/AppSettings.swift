import Foundation
import Combine

// MARK: - AppSettings

struct AppSettings: Codable {
    /// Utilization percentage at which the UI switches to a warning state (default: 80%)
    var warningThreshold: Double = 80
    /// Utilization percentage at which the UI switches to a critical state (default: 90%)
    var criticalThreshold: Double = 90
    /// Whether to post system notifications when thresholds are crossed (default: true)
    var notificationsEnabled: Bool = true
}

// MARK: - SettingsManager

final class SettingsManager: ObservableObject {

    // MARK: Singleton

    static let shared = SettingsManager()

    // MARK: Published state

    @Published var settings: AppSettings

    // MARK: Private

    private static let userDefaultsKey = "ClaudeUsageBarSettings"

    // MARK: Init

    private init() {
        settings = Self.load()
    }

    // MARK: Public API

    /// Persists the current settings to UserDefaults.
    func save() {
        guard let encoded = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(encoded, forKey: Self.userDefaultsKey)
    }

    /// Resets settings to compiled-in defaults and persists the change.
    func resetToDefaults() {
        settings = AppSettings()
        save()
    }

    // MARK: Private helpers

    private static func load() -> AppSettings {
        guard
            let data = UserDefaults.standard.data(forKey: userDefaultsKey),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }
        return decoded
    }
}
