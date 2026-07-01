// Tests/ClaudeUsageBarTests/UsageForecasterTests.swift
import XCTest
@testable import ClaudeUsageBar

final class UsageForecasterTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_000_000_000)

    private func rec(_ secondsAgo: TimeInterval, _ five: Int) -> UsageHistoryRecord {
        UsageHistoryRecord(
            timestamp: now.addingTimeInterval(-secondsAgo),
            fiveHourUtilization: five, sevenDayUtilization: 0, sonnetUtilization: nil
        )
    }

    func testRisingProducesTimeToLimit() {
        // 60% an hour ago, 80% now → +20%/hour. 20% headroom → ~1h to 100%.
        let records = [rec(3600, 60), rec(0, 80)]
        let f = UsageForecaster.forecast(
            records: records, value: \.fiveHourUtilization,
            current: 80, resetsAt: nil, now: now)
        XCTAssertEqual(f.trend, .rising)
        let t = try? XCTUnwrap(f.timeToLimit)
        XCTAssertEqual(t ?? 0, 3600, accuracy: 60, "Expected ~1h to limit")
        XCTAssertNil(f.projectedAtReset)
    }

    func testFlatIsSteady() {
        let records = [rec(3600, 50), rec(1800, 50), rec(0, 50)]
        let f = UsageForecaster.forecast(
            records: records, value: \.fiveHourUtilization,
            current: 50, resetsAt: nil, now: now)
        XCTAssertEqual(f.trend, .steady)
        XCTAssertNil(f.timeToLimit)
    }

    func testDecliningIsDeclining() {
        let records = [rec(3600, 80), rec(0, 60)]
        let f = UsageForecaster.forecast(
            records: records, value: \.fiveHourUtilization,
            current: 60, resetsAt: nil, now: now)
        XCTAssertEqual(f.trend, .declining)
        XCTAssertNil(f.timeToLimit)
    }

    func testResetBeforeLimitProjectsInstead() {
        // Slow climb: 50% → 55% over an hour (+5%/h). Headroom 45% → ~9h to limit,
        // but the window resets in 1h, so expect a projection, not a timeToLimit.
        let records = [rec(3600, 50), rec(0, 55)]
        let resetsAt = now.addingTimeInterval(3600)
        let f = UsageForecaster.forecast(
            records: records, value: \.fiveHourUtilization,
            current: 55, resetsAt: resetsAt, now: now)
        XCTAssertEqual(f.trend, .rising)
        XCTAssertNil(f.timeToLimit, "Resets before the limit → no ETA")
        let p = try? XCTUnwrap(f.projectedAtReset)
        XCTAssertEqual(p ?? 0, 60, accuracy: 1, "55% + 5%/h over 1h ≈ 60%")
    }

    func testInsufficientDataIsSteady() {
        let f = UsageForecaster.forecast(
            records: [rec(0, 80)], value: \.fiveHourUtilization,
            current: 80, resetsAt: nil, now: now)
        XCTAssertEqual(f.trend, .steady)
        XCTAssertNil(f.timeToLimit)
    }
}
