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
        XCTAssertEqual(snapshot.scopedLimits.first?.utilization, 89,
                       "Legacy sonnet should fall back to a scoped limit at 89 (rounded from 88.9)")
        XCTAssertEqual(snapshot.scopedLimits.first?.label, "Sonnet")

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
        XCTAssertTrue(snapshot.scopedLimits.isEmpty,
                      "scopedLimits should be empty when no limits or sevenDaySonnet exist")
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
        XCTAssertEqual(snapshot.scopedLimits.first?.utilization, 100)
    }

    // MARK: - testPlaceholder

    func testPlaceholder() {
        let snapshot = UsageSnapshot.placeholder

        XCTAssertEqual(snapshot.fiveHourUtilization, 0)
        XCTAssertEqual(snapshot.sevenDayUtilization, 0)
        XCTAssertTrue(snapshot.scopedLimits.isEmpty)
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

    // MARK: - Scoped limits

    private func decode(_ json: String) throws -> OAuthUsageResponse {
        try JSONDecoder().decode(OAuthUsageResponse.self, from: Data(json.utf8))
    }

    func testDecodesSampleLimitsIntoFableScopedLimit() throws {
        let json = """
        {"five_hour":null,"seven_day":null,"seven_day_sonnet":null,
         "limits":[
          {"kind":"session","group":"session","percent":26,"severity":"normal","resets_at":"2099-10-09T09:50:00.463454+00:00","scope":null,"is_active":false},
          {"kind":"weekly_all","group":"weekly","percent":47,"severity":"normal","resets_at":"2099-10-13T05:00:00.463476+00:00","scope":null,"is_active":false},
          {"kind":"weekly_scoped","group":"weekly","percent":80,"severity":"warning","resets_at":"2099-10-13T05:00:00.463633+00:00","scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":true}
         ]}
        """
        let snapshot = UsageSnapshot.from(response: try decode(json))
        XCTAssertEqual(snapshot.scopedLimits.count, 1)
        XCTAssertEqual(snapshot.scopedLimits[0].label, "Fable")
        XCTAssertEqual(snapshot.scopedLimits[0].utilization, 80)
        XCTAssertNotNil(snapshot.scopedLimits[0].resetIn)
        XCTAssertNotNil(snapshot.scopedLimits[0].resetsAt)
    }

    func testNullOrAbsentLimitsYieldsEmpty() throws {
        XCTAssertTrue(UsageSnapshot.from(response: try decode("{}")).scopedLimits.isEmpty)
        XCTAssertTrue(UsageSnapshot.from(response: try decode(#"{"limits":null}"#)).scopedLimits.isEmpty)
    }

    func testMalformedLimitEntriesDoNotBreakDecoding() throws {
        let json = """
        {"five_hour":{"utilization":10,"resets_at":"2099-01-01T00:00:00Z"},
         "limits":["junk", 5, null, {},
          {"kind":"mystery","percent":"x"},
          {"kind":"weekly_scoped","percent":150,"scope":{"model":null,"surface":null}},
          {"kind":"weekly_scoped","percent":30,"scope":{"model":{"display_name":null},"surface":{"display_name":"CLI"}}}]}
        """
        let response = try decode(json)
        XCTAssertEqual(response.fiveHour?.utilization, 10)
        let snapshot = UsageSnapshot.from(response: response)
        XCTAssertEqual(snapshot.scopedLimits.map(\.label), ["Scoped", "CLI"])
        XCTAssertEqual(snapshot.scopedLimits.map(\.utilization), [100, 30])
    }

    func testNonArrayLimitsDoesNotBreakDecoding() throws {
        let response = try decode(#"{"limits":"nope","seven_day":{"utilization":5,"resets_at":"2099-01-01T00:00:00Z"}}"#)
        XCTAssertEqual(response.sevenDay?.utilization, 5)
        XCTAssertTrue(UsageSnapshot.from(response: response).scopedLimits.isEmpty)
    }

    func testLegacySonnetFallbackOnlyWhenNoScopedLimits() {
        let legacy = makeResponse(sevenDaySonnet: makePeriod(utilization: 42))
        XCTAssertEqual(UsageSnapshot.from(response: legacy).scopedLimits.map(\.label), ["Sonnet"])

        let scoped = OAuthUsageResponse(
            sevenDaySonnet: makePeriod(utilization: 42),
            limits: [UsageLimit(kind: "weekly_scoped", percent: 80,
                                scope: .init(model: .init(displayName: "Fable")))]
        )
        XCTAssertEqual(UsageSnapshot.from(response: scoped).scopedLimits.map(\.label), ["Fable"])
    }
}
