import Foundation

/// Response from GET https://api.anthropic.com/api/oauth/usage
struct OAuthUsageResponse: Codable {
    let fiveHour: UsagePeriod?
    let sevenDay: UsagePeriod?
    let sevenDaySonnet: UsagePeriod?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}

/// Usage data for a specific time period
struct UsagePeriod: Codable {
    /// Utilization percentage from 0 to 100
    let utilization: Double
    /// ISO8601 timestamp indicating when this period resets
    let resetsAt: String

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}
