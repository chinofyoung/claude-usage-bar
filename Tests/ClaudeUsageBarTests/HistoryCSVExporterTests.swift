// Tests/ClaudeUsageBarTests/HistoryCSVExporterTests.swift
import XCTest
@testable import ClaudeUsageBar

final class HistoryCSVExporterTests: XCTestCase {

    func testHeaderAndRowCount() {
        let recs = [
            UsageHistoryRecord(timestamp: Date(timeIntervalSince1970: 0),
                               fiveHourUtilization: 10, sevenDayUtilization: 20, sonnetUtilization: 30),
            UsageHistoryRecord(timestamp: Date(timeIntervalSince1970: 60),
                               fiveHourUtilization: 11, sevenDayUtilization: 21, sonnetUtilization: nil)
        ]
        let csv = HistoryCSVExporter.csv(from: recs)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.first, "timestamp,five_hour,seven_day,seven_day_sonnet")
        XCTAssertEqual(lines.count, 3, "Header + 2 data rows")
    }

    func testNilSonnetIsEmptyField() {
        let recs = [UsageHistoryRecord(timestamp: Date(timeIntervalSince1970: 0),
                    fiveHourUtilization: 1, sevenDayUtilization: 2, sonnetUtilization: nil)]
        let csv = HistoryCSVExporter.csv(from: recs)
        XCTAssertTrue(csv.contains(",1,2,\n") || csv.hasSuffix(",1,2,\n"),
                      "nil Sonnet should render as a trailing empty field")
    }

    func testSortsAscendingByTimestamp() {
        let recs = [
            UsageHistoryRecord(timestamp: Date(timeIntervalSince1970: 100),
                               fiveHourUtilization: 9, sevenDayUtilization: 9, sonnetUtilization: nil),
            UsageHistoryRecord(timestamp: Date(timeIntervalSince1970: 0),
                               fiveHourUtilization: 1, sevenDayUtilization: 1, sonnetUtilization: nil)
        ]
        let lines = HistoryCSVExporter.csv(from: recs).split(separator: "\n").map(String.init)
        XCTAssertTrue(lines[1].contains(",1,1,"), "Earliest record must come first")
    }
}
