import XCTest
@testable import ClaudeUsageBar

final class UsageHistoryRecordTests: XCTestCase {

    func testDecodesLegacyRecordWithoutSonnet() throws {
        // JSON produced by the OLD 2-field struct (no sonnetUtilization key).
        let json = """
        [{"timestamp": 0, "fiveHourUtilization": 40, "sevenDayUtilization": 55}]
        """.data(using: .utf8)!

        let records = try JSONDecoder().decode([UsageHistoryRecord].self, from: json)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].fiveHourUtilization, 40)
        XCTAssertEqual(records[0].sevenDayUtilization, 55)
        XCTAssertNil(records[0].sonnetUtilization,
                     "Legacy records lack the key and must decode to nil")
    }

    func testRoundTripsSonnet() throws {
        let record = UsageHistoryRecord(
            timestamp: Date(timeIntervalSince1970: 100),
            fiveHourUtilization: 10,
            sevenDayUtilization: 20,
            sonnetUtilization: 30
        )
        let data = try JSONEncoder().encode([record])
        let decoded = try JSONDecoder().decode([UsageHistoryRecord].self, from: data)
        XCTAssertEqual(decoded[0].sonnetUtilization, 30)
    }
}
