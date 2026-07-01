import XCTest
@testable import ClaudeUsageBar

final class UsageSnapshotTests: XCTestCase {

    // MARK: - Helpers

    /// Returns an ISO8601 string for a date that is `secondsFromNow` seconds in the future.
    private func futureISO8601(secondsFromNow: TimeInterval = 7200) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date(timeIntervalSinceNow: secondsFromNow))
    }

    /// Builds an OAuthUsageResponse directly via its synthesised memberwise initialiser,
    /// which is accessible because @testable import grants internal-level access.
    private func makeResponse(
        fiveHour: UsagePeriod? = nil,
        sevenDay: UsagePeriod? = nil,
        sevenDaySonnet: UsagePeriod? = nil
    ) -> OAuthUsageResponse {
        OAuthUsageResponse(fiveHour: fiveHour, sevenDay: sevenDay, sevenDaySonnet: sevenDaySonnet)
    }

    // UsagePeriod is a top-level struct (not nested inside OAuthUsageResponse).
    private func makePeriod(utilization: Double, resetsAt: String? = nil) -> UsagePeriod {
        UsagePeriod(utilization: utilization, resetsAt: resetsAt ?? futureISO8601())
    }

    // MARK: - testFromResponse_fullData

    func testFromResponse_fullData() {
        let resetString = futureISO8601(secondsFromNow: 7200)   // 2 hours from now

        let response = makeResponse(
            fiveHour: makePeriod(utilization: 45.6, resetsAt: resetString),
            sevenDay: makePeriod(utilization: 72.3, resetsAt: resetString),
            sevenDaySonnet: makePeriod(utilization: 88.9, resetsAt: resetString)
        )

        let snapshot = UsageSnapshot.from(response: response)

        // Utilisation values should be rounded integers
        XCTAssertEqual(snapshot.fiveHourUtilization, 46,
                       "Expected fiveHourUtilization to be 46 (rounded from 45.6)")
        XCTAssertEqual(snapshot.sevenDayUtilization, 72,
                       "Expected sevenDayUtilization to be 72 (rounded from 72.3)")
        XCTAssertEqual(snapshot.sonnetUtilization, 89,
                       "Expected sonnetUtilization to be 89 (rounded from 88.9)")

        // Reset strings should be non-nil because the dates are in the future
        XCTAssertNotNil(snapshot.fiveHourResetIn,  "fiveHourResetIn should be non-nil for a future reset date")
        XCTAssertNotNil(snapshot.sevenDayResetIn,  "sevenDayResetIn should be non-nil for a future reset date")

        // lastUpdated should be very recent
        XCTAssertLessThan(abs(snapshot.lastUpdated.timeIntervalSinceNow), 2,
                          "lastUpdated should be within 2 seconds of now")
    }

    // MARK: - testFromResponse_partialData

    func testFromResponse_partialData() {
        // Only sevenDay is present; fiveHour and sevenDaySonnet default to nil
        let response = makeResponse(
            sevenDay: makePeriod(utilization: 60.0)
        )

        let snapshot = UsageSnapshot.from(response: response)

        XCTAssertEqual(snapshot.fiveHourUtilization, 0,
                       "fiveHourUtilization should be 0 when fiveHour period is absent")
        XCTAssertEqual(snapshot.sevenDayUtilization, 60)
        XCTAssertNil(snapshot.sonnetUtilization,
                     "sonnetUtilization should be nil when sevenDaySonnet period is absent")
        XCTAssertNil(snapshot.fiveHourResetIn,
                     "fiveHourResetIn should be nil when fiveHour period is absent")
    }

    // MARK: - testFromResponse_clampsValues

    func testFromResponse_clampsValues() {
        let response = makeResponse(
            fiveHour: makePeriod(utilization: 150.0),   // above 100 → should clamp to 100
            sevenDay: makePeriod(utilization: -25.0),   // below 0   → should clamp to 0
            sevenDaySonnet: makePeriod(utilization: 100.0)
        )

        let snapshot = UsageSnapshot.from(response: response)

        XCTAssertEqual(snapshot.fiveHourUtilization, 100,
                       "Utilization > 100 should be clamped to 100")
        XCTAssertEqual(snapshot.sevenDayUtilization, 0,
                       "Utilization < 0 should be clamped to 0")
        XCTAssertEqual(snapshot.sonnetUtilization, 100)
    }

    // MARK: - testPlaceholder

    func testPlaceholder() {
        let snapshot = UsageSnapshot.placeholder

        XCTAssertEqual(snapshot.fiveHourUtilization, 0)
        XCTAssertEqual(snapshot.sevenDayUtilization, 0)
        XCTAssertNil(snapshot.sonnetUtilization)
        XCTAssertNil(snapshot.fiveHourResetIn)
        XCTAssertNil(snapshot.sevenDayResetIn)
    }

    // MARK: - testFromResponse_populatesResetDates

    func testFromResponse_populatesResetDates() {
        let resetString = futureISO8601(secondsFromNow: 7200)   // 2h from now
        let response = makeResponse(
            fiveHour: makePeriod(utilization: 30, resetsAt: resetString),
            sevenDay: makePeriod(utilization: 40, resetsAt: resetString)
        )
        let snapshot = UsageSnapshot.from(response: response)

        XCTAssertNotNil(snapshot.fiveHourResetsAt, "Should parse a Date for the 5h reset")
        XCTAssertNotNil(snapshot.sevenDayResetsAt)
        let secs = snapshot.fiveHourResetsAt!.timeIntervalSinceNow
        XCTAssertEqual(secs, 7200, accuracy: 5, "Parsed reset date should be ~2h out")
    }
}
