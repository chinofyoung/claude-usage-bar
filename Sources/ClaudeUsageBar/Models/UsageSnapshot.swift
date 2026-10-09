import Foundation

/// A weekly limit scoped to a specific model.
struct ScopedLimit: Equatable {
    /// Display name of the model, e.g. "Fable"
    let label: String
    /// Utilization, 0-100
    let utilization: Int
    /// Human-readable time until reset
    let resetIn: String?
    /// Absolute reset time, when known
    let resetsAt: Date?
}

struct UsageSnapshot {
    /// 5-hour rolling utilization, 0-100
    let fiveHourUtilization: Int
    /// 7-day rolling utilization, 0-100
    let sevenDayUtilization: Int
    /// Per-model weekly limits (e.g. "Fable"); empty when none are reported
    let scopedLimits: [ScopedLimit]
    /// Human-readable time until the 5-hour window resets, e.g. "2h 15m"
    let fiveHourResetIn: String?
    /// Human-readable time until the 7-day window resets, e.g. "3d 4h"
    let sevenDayResetIn: String?
    /// Absolute time the 5-hour window resets, when known.
    let fiveHourResetsAt: Date?
    /// Absolute time the 7-day window resets, when known.
    let sevenDayResetsAt: Date?
    /// When this snapshot was captured
    let lastUpdated: Date

    // MARK: - Factory

    static func from(response: OAuthUsageResponse) -> UsageSnapshot {
        let now = Date()

        return UsageSnapshot(
            fiveHourUtilization: clamp(response.fiveHour?.utilization),
            sevenDayUtilization: clamp(response.sevenDay?.utilization),
            scopedLimits: scopedLimits(from: response, relativeTo: now),
            fiveHourResetIn: response.fiveHour.flatMap { formatCountdown(from: $0.resetsAt, relativeTo: now) },
            sevenDayResetIn: response.sevenDay.flatMap { formatCountdown(from: $0.resetsAt, relativeTo: now) },
            fiveHourResetsAt: response.fiveHour.flatMap { parseFutureDate(from: $0.resetsAt, relativeTo: now) },
            sevenDayResetsAt: response.sevenDay.flatMap { parseFutureDate(from: $0.resetsAt, relativeTo: now) },
            lastUpdated: now
        )
    }

    private static func scopedLimits(from response: OAuthUsageResponse, relativeTo now: Date) -> [ScopedLimit] {
        let scoped = (response.limits ?? [])
            .filter { $0.kind == "weekly_scoped" }
            .map { limit -> ScopedLimit in
                let name = [limit.scope?.model?.displayName, limit.scope?.surface?.displayName]
                    .compactMap { $0 }
                    .first { !$0.isEmpty } ?? "Scoped"
                return ScopedLimit(
                    label: name,
                    utilization: clamp(limit.percent),
                    resetIn: limit.resetsAt.flatMap { formatCountdown(from: $0, relativeTo: now) },
                    resetsAt: limit.resetsAt.flatMap { parseFutureDate(from: $0, relativeTo: now) }
                )
            }
        if !scoped.isEmpty { return scoped }

        // Legacy fallback for responses that only carry seven_day_sonnet.
        guard let sonnet = response.sevenDaySonnet else { return [] }
        return [ScopedLimit(
            label: "Sonnet",
            utilization: clamp(sonnet.utilization),
            resetIn: formatCountdown(from: sonnet.resetsAt, relativeTo: now),
            resetsAt: parseFutureDate(from: sonnet.resetsAt, relativeTo: now)
        )]
    }

    static var placeholder: UsageSnapshot {
        UsageSnapshot(
            fiveHourUtilization: 0,
            sevenDayUtilization: 0,
            scopedLimits: [],
            fiveHourResetIn: nil,
            sevenDayResetIn: nil,
            fiveHourResetsAt: nil,
            sevenDayResetsAt: nil,
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

/// Parses an ISO8601 timestamp into a future `Date`, tolerating fractional seconds.
/// Returns nil if unparseable or already in the past.
private func parseFutureDate(from iso8601: String, relativeTo now: Date) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = formatter.date(from: iso8601)
    if date == nil {
        formatter.formatOptions = [.withInternetDateTime]
        date = formatter.date(from: iso8601)
    }
    guard let date, date > now else { return nil }
    return date
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
