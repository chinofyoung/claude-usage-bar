import Foundation
import Combine

// MARK: - Enums

enum StatusBarStyle: String, Codable, CaseIterable {
    case normal = "Normal"
    case compact = "Compact"
    case minimal = "Minimal"
}

enum ProgressBarHeight: String, Codable, CaseIterable {
    case thin = "Thin"
    case normal = "Normal"
    case thick = "Thick"

    var points: CGFloat {
        switch self {
        case .thin: return 2
        case .normal: return 4
        case .thick: return 6
        }
    }
}

enum PopoverWidth: String, Codable, CaseIterable {
    case compact = "Compact"
    case normal = "Normal"
    case wide = "Wide"

    var points: CGFloat {
        switch self {
        case .compact: return 200
        case .normal: return 240
        case .wide: return 280
        }
    }
}

enum AccentColorOption: String, Codable, CaseIterable {
    case green = "Green"
    case blue = "Blue"
    case purple = "Purple"
    case teal = "Teal"
    case system = "System"
}

// MARK: - AppSettings

struct AppSettings: Codable {
    /// Utilization percentage at which the UI switches to a warning state (default: 80%)
    var warningThreshold: Double = 80
    /// Utilization percentage at which the UI switches to a critical state (default: 90%)
    var criticalThreshold: Double = 90
    /// Whether to post system notifications when thresholds are crossed (default: true)
    var notificationsEnabled: Bool = true
    /// Whether to show SF Symbol icons in the status bar and popover (default: true)
    /// Only applies when statusBarStyle == .normal
    var useIcons: Bool = true
    var pollInterval: TimeInterval = 300
    var launchAtLogin: Bool = false

    // MARK: Status Bar Display
    var statusBarStyle: StatusBarStyle = .normal
    var showFiveHour: Bool = true
    var showSevenDay: Bool = true
    var showSonnet: Bool = true

    // MARK: Popover Appearance
    var showSparklines: Bool = true
    var progressBarHeight: ProgressBarHeight = .normal
    var popoverWidth: PopoverWidth = .normal
    var accentColor: AccentColorOption = .green
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
