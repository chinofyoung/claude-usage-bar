import XCTest
@testable import ClaudeUsageBar

/// Tests for the AppSettings value type in isolation.
/// The SettingsManager singleton is intentionally not exercised here to avoid
/// polluting UserDefaults in the host application's standard suite.
final class SettingsManagerTests: XCTestCase {

    // MARK: - testDefaultValues

    func testDefaultValues() {
        let settings = AppSettings()

        XCTAssertEqual(settings.warningThreshold, 80,
                       "Default warningThreshold should be 80")
        XCTAssertEqual(settings.criticalThreshold, 90,
                       "Default criticalThreshold should be 90")
        XCTAssertTrue(settings.notificationsEnabled,
                      "Default notificationsEnabled should be true")
        XCTAssertEqual(settings.statusBarStyle, .normal,
                       "Default statusBarStyle should be .normal")
    }

    // MARK: - testCodableRoundTrip

    func testCodableRoundTrip() throws {
        var original = AppSettings()
        original.warningThreshold = 65
        original.criticalThreshold = 85
        original.notificationsEnabled = false
        original.statusBarStyle = .compact

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        XCTAssertEqual(decoded.warningThreshold, 65,
                       "warningThreshold should survive JSON round-trip")
        XCTAssertEqual(decoded.criticalThreshold, 85,
                       "criticalThreshold should survive JSON round-trip")
        XCTAssertFalse(decoded.notificationsEnabled,
                       "notificationsEnabled should survive JSON round-trip")
        XCTAssertEqual(decoded.statusBarStyle, .compact,
                       "statusBarStyle should survive JSON round-trip")
    }
}
