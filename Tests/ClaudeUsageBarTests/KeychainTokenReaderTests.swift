import XCTest
@testable import ClaudeUsageBar

/// Tests for KeychainTokenReader.isExpiredOrNearExpiry(_:now:).
///
/// All tests use a fixed `now` so they are deterministic regardless of
/// when they run.  The regression test (testExpiredWhenExpiresAtMillisIsInPast)
/// specifically exercises the ms-vs-seconds unit mismatch: the raw millisecond
/// value is numerically larger than `now` in seconds, so the old buggy code
/// would evaluate the token as unexpired — the fixed code converts first.
final class KeychainTokenReaderTests: XCTestCase {

    // MARK: - Fixture

    /// A fixed reference point: 2023-11-14 22:13:20 UTC (Unix seconds).
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Tests

    /// Regression test for the ms-vs-seconds bug.
    ///
    /// expiresAt = 1_699_990_000_000 ms
    ///   → in seconds: 1_699_990_000  (10 000 seconds BEFORE `now`)   → EXPIRED
    ///   → raw value:  1_699_990_000_000  >> now (1_700_000_000)       → old code: NOT expired (wrong)
    func testExpiredWhenExpiresAtMillisIsInPast() {
        let expiresAtMillis: Double = 1_699_990_000_000  // 10 000 seconds before `now` in ms
        XCTAssertTrue(
            KeychainTokenReader.isExpiredOrNearExpiry(expiresAtMillis, now: now),
            "A token whose expiry is in the past (in ms) must be considered expired"
        )
    }

    /// A token that expires far in the future (in ms) must NOT be considered expired.
    func testNotExpiredWhenExpiresAtMillisIsFarFuture() {
        // now + 3600 seconds, expressed in milliseconds
        let expiresAtMillis: Double = (1_700_000_000 + 3_600) * 1_000
        XCTAssertFalse(
            KeychainTokenReader.isExpiredOrNearExpiry(expiresAtMillis, now: now),
            "A token expiring 3600 s from now must not be considered expired"
        )
    }

    /// A token that expires within the 60-second margin must be treated as expired.
    func testExpiredWithinMargin() {
        // Token expires 30 seconds after `now` — inside the 60-second margin.
        let expiresAtMillis: Double = (1_700_000_000 + 30) * 1_000
        XCTAssertTrue(
            KeychainTokenReader.isExpiredOrNearExpiry(expiresAtMillis, now: now),
            "A token expiring within the 60-second margin must be considered expired"
        )
    }
}
