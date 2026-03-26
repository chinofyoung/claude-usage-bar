import Foundation

struct UsageSnapshot {
    /// 5-hour rolling utilization, 0-100
    let fiveHourUtilization: Int
    /// 7-day rolling utilization, 0-100
    let sevenDayUtilization: Int
    /// Sonnet-specific 7-day utilization, 0-100 (absent when not returned by API)
    let sonnetUtilization: Int?
    /// Human-readable time until the 5-hour window resets, e.g. "2h 15m"
    let fiveHourResetIn: String?
    /// Human-readable time until the 7-day window resets, e.g. "3d 4h"
    let sevenDayResetIn: String?
    /// When this snapshot was captured
    let lastUpdated: Date

    // MARK: - Factory

    static func from(response: OAuthUsageResponse) -> UsageSnapshot {
        let now = Date()

        return UsageSnapshot(
            fiveHourUtilization: clamp(response.fiveHour?.utilization),
            sevenDayUtilization: clamp(response.sevenDay?.utilization),
            sonnetUtilization: response.sevenDaySonnet.map { clamp($0.utilization) },
            fiveHourResetIn: response.fiveHour.flatMap { formatCountdown(from: $0.resetsAt, relativeTo: now) },
            sevenDayResetIn: response.sevenDay.flatMap { formatCountdown(from: $0.resetsAt, relativeTo: now) },
            lastUpdated: now
        )
    }

    static var placeholder: UsageSnapshot {
        UsageSnapshot(
            fiveHourUtilization: 0,
            sevenDayUtilization: 0,
            sonnetUtilization: nil,
            fiveHourResetIn: nil,
            sevenDayResetIn: nil,
            lastUpdated: Date()
        )
    }
}

// MARK: - Helpers

/// Clamps an optional Double percentage into a 0-100 Int.
private func clamp(_ value: Double?) -> Int {
    guard let value else { return 0 }
    return Int(min(100, max(0, value)).rounded())
}

/// Parses an ISO8601 timestamp and returns a human-readable countdown string
/// relative to `now`. Returns nil if the string cannot be parsed or the date
/// is already in the past.
private func formatCountdown(from iso8601: String, relativeTo now: Date) -> String? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    var resetDate = formatter.date(from: iso8601)

    if resetDate == nil {
        // Retry without fractional seconds for servers that omit them
        formatter.formatOptions = [.withInternetDateTime]
        resetDate = formatter.date(from: iso8601)
    }

    guard let resetDate, resetDate > now else { return nil }

    let totalSeconds = Int(resetDate.timeIntervalSince(now))
    return formatDuration(seconds: totalSeconds)
}

/// Converts a duration in seconds to a compact human-readable string.
/// Examples: "4h 30m", "2d 3h", "45m", "3d"
private func formatDuration(seconds: Int) -> String {
    let minutes = seconds / 60
    let hours = minutes / 60
    let days = hours / 24

    let remainingHours = hours % 24
    let remainingMinutes = minutes % 60

    switch (days, remainingHours, remainingMinutes) {
    case let (d, h, _) where d > 0 && h > 0:
        return "\(d)d \(h)h"
    case let (d, _, _) where d > 0:
        return "\(d)d"
    case let (_, h, m) where h > 0 && m > 0:
        return "\(h)h \(m)m"
    case let (_, h, _) where h > 0:
        return "\(h)h"
    default:
        return "\(remainingMinutes)m"
    }
}
