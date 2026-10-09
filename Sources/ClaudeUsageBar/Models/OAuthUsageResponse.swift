import Foundation

/// Response from GET https://api.anthropic.com/api/oauth/usage
struct OAuthUsageResponse: Decodable {
    let fiveHour: UsagePeriod?
    let sevenDay: UsagePeriod?
    let sevenDaySonnet: UsagePeriod?
    /// Generic limits list (session, weekly, per-model weekly). Nil when absent.
    let limits: [UsageLimit]?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case limits
    }

    init(fiveHour: UsagePeriod? = nil,
         sevenDay: UsagePeriod? = nil,
         sevenDaySonnet: UsagePeriod? = nil,
         limits: [UsageLimit]? = nil) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDaySonnet = sevenDaySonnet
        self.limits = limits
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try c.decodeIfPresent(UsagePeriod.self, forKey: .fiveHour)
        sevenDay = try c.decodeIfPresent(UsagePeriod.self, forKey: .sevenDay)
        sevenDaySonnet = try c.decodeIfPresent(UsagePeriod.self, forKey: .sevenDaySonnet)
        // Lenient: a malformed/non-array `limits` must never break the whole response.
        limits = (try? c.decodeIfPresent([LossyLimit].self, forKey: .limits))?
            .map { $0.value }
    }
}

/// Decodes a limit entry, yielding an empty limit when the entry is malformed.
private struct LossyLimit: Decodable {
    let value: UsageLimit
    init(from decoder: Decoder) throws {
        value = (try? UsageLimit(from: decoder)) ?? UsageLimit()
    }
}

/// One entry of the `limits` array. Every field is optional so unknown
/// kinds or missing fields never break decoding.
struct UsageLimit: Decodable {
    let kind: String?
    let group: String?
    let percent: Double?
    let resetsAt: String?
    let scope: Scope?

    struct Scope: Decodable {
        let model: Model?
        let surface: Surface?

        init(model: Model? = nil, surface: Surface? = nil) {
            self.model = model
            self.surface = surface
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            model = try? c.decodeIfPresent(Model.self, forKey: .model)
            surface = try? c.decodeIfPresent(Surface.self, forKey: .surface)
        }

        enum CodingKeys: String, CodingKey { case model, surface }
    }

    struct Model: Decodable {
        let displayName: String?
        init(displayName: String? = nil) { self.displayName = displayName }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            displayName = try? c.decodeIfPresent(String.self, forKey: .displayName)
        }
        enum CodingKeys: String, CodingKey { case displayName = "display_name" }
    }

    struct Surface: Decodable {
        let displayName: String?
        init(displayName: String? = nil) { self.displayName = displayName }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            displayName = try? c.decodeIfPresent(String.self, forKey: .displayName)
        }
        enum CodingKeys: String, CodingKey { case displayName = "display_name" }
    }

    init(kind: String? = nil, group: String? = nil, percent: Double? = nil,
         resetsAt: String? = nil, scope: Scope? = nil) {
        self.kind = kind
        self.group = group
        self.percent = percent
        self.resetsAt = resetsAt
        self.scope = scope
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        group = try? c.decodeIfPresent(String.self, forKey: .group)
        percent = try? c.decodeIfPresent(Double.self, forKey: .percent)
        resetsAt = try? c.decodeIfPresent(String.self, forKey: .resetsAt)
        scope = try? c.decodeIfPresent(Scope.self, forKey: .scope)
    }

    enum CodingKeys: String, CodingKey {
        case kind, group, percent, scope
        case resetsAt = "resets_at"
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
