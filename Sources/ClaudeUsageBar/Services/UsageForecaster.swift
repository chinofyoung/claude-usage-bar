import Foundation

struct UsageForecast {
    enum Trend { case rising, steady, declining }
    let trend: Trend
    /// Seconds until utilization is projected to reach 100%, when it hits the cap before resetting.
    let timeToLimit: TimeInterval?
    /// Projected utilization (%) at the reset moment, when the window resets before hitting 100%.
    let projectedAtReset: Double?
}

enum UsageForecaster {
    /// Treat anything slower than 1% per hour as flat.
    private static let epsilon = 1.0 / 3600.0   // %/sec

    static func forecast(
        records: [UsageHistoryRecord],
        value: KeyPath<UsageHistoryRecord, Int>,
        current: Int,
        resetsAt: Date?,
        now: Date,
        window: TimeInterval = 3600
    ) -> UsageForecast {
        let windowStart = now.addingTimeInterval(-window)
        let points = records
            .filter { $0.timestamp >= windowStart && $0.timestamp <= now }
            .sorted { $0.timestamp < $1.timestamp }

        guard points.count >= 2 else {
            return UsageForecast(trend: .steady, timeToLimit: nil, projectedAtReset: nil)
        }

        // Least-squares slope of utilization (%) vs time (sec).
        let t0 = points[0].timestamp
        let xs = points.map { $0.timestamp.timeIntervalSince(t0) }
        let ys = points.map { Double($0[keyPath: value]) }
        let n = Double(points.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = xs.reduce(0) { $0 + $1 * $1 }
        let denom = n * sumX2 - sumX * sumX
        guard denom != 0 else {
            return UsageForecast(trend: .steady, timeToLimit: nil, projectedAtReset: nil)
        }
        let slope = (n * sumXY - sumX * sumY) / denom   // %/sec

        if slope <= -epsilon {
            return UsageForecast(trend: .declining, timeToLimit: nil, projectedAtReset: nil)
        }
        if slope < epsilon {
            return UsageForecast(trend: .steady, timeToLimit: nil, projectedAtReset: nil)
        }

        // Rising.
        let headroom = Double(100 - current)
        let secondsToLimit = headroom / slope
        if let resetsAt, resetsAt < now.addingTimeInterval(secondsToLimit) {
            let projected = min(100.0, Double(current) + slope * resetsAt.timeIntervalSince(now))
            return UsageForecast(trend: .rising, timeToLimit: nil, projectedAtReset: projected)
        }
        return UsageForecast(trend: .rising, timeToLimit: secondsToLimit, projectedAtReset: nil)
    }
}
