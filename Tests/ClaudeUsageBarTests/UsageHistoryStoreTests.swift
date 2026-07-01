// Tests/ClaudeUsageBarTests/UsageHistoryStoreTests.swift
import XCTest
@testable import ClaudeUsageBar

@MainActor
final class UsageHistoryStoreTests: XCTestCase {

    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("hist-\(UUID().uuidString).json")
    }

    private func ephemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    }

    private func record(_ secondsAgo: TimeInterval, now: Date) -> UsageHistoryRecord {
        UsageHistoryRecord(
            timestamp: now.addingTimeInterval(-secondsAgo),
            fiveHourUtilization: 50, sevenDayUtilization: 50, sonnetUtilization: nil
        )
    }

    func testTrimsRecordsOlderThan30Days() {
        let url = tempFileURL()
        let store = UsageHistoryStore(fileURL: url, userDefaults: ephemeralDefaults())
        let now = Date(timeIntervalSince1970: 1_000_000_000)

        store.append(record: record(31 * 86400, now: now), now: now)  // too old
        store.append(record: record(1 * 86400, now: now), now: now)   // recent

        XCTAssertEqual(store.records.count, 1, "31-day-old record must be trimmed")
        XCTAssertEqual(Int(now.timeIntervalSince(store.records[0].timestamp)), 86400)
    }

    func testPersistsAcrossInstances() {
        let url = tempFileURL()
        let defaults = ephemeralDefaults()
        let now = Date(timeIntervalSince1970: 1_000_000_000)

        let store1 = UsageHistoryStore(fileURL: url, userDefaults: defaults)
        store1.append(record: record(3600, now: now), now: now)

        let store2 = UsageHistoryStore(fileURL: url, userDefaults: defaults)
        XCTAssertEqual(store2.records.count, 1, "Records must load from the file on init")
    }

    func testMigratesLegacyUserDefaultsRecords() {
        let url = tempFileURL()                  // does NOT exist yet
        let defaults = ephemeralDefaults()
        let legacy = """
        [{"timestamp": 0, "fiveHourUtilization": 11, "sevenDayUtilization": 22}]
        """.data(using: .utf8)!
        defaults.set(legacy, forKey: "ClaudeUsageBarHistory")

        let store = UsageHistoryStore(fileURL: url, userDefaults: defaults)

        XCTAssertEqual(store.records.count, 1, "Legacy record should migrate into the file")
        XCTAssertEqual(store.records[0].fiveHourUtilization, 11)
        XCTAssertNil(defaults.data(forKey: "ClaudeUsageBarHistory"),
                     "Legacy key must be cleared after migration")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "Migration must write the history file")
    }

    func testMigrationNoOpsWhenFileExists() {
        let url = tempFileURL()
        let defaults = ephemeralDefaults()
        // Pre-existing file with one record.
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let store1 = UsageHistoryStore(fileURL: url, userDefaults: defaults)
        store1.append(record: record(3600, now: now), now: now)
        // Now legacy data appears, but file already exists.
        defaults.set("[{\"timestamp\":0,\"fiveHourUtilization\":99,\"sevenDayUtilization\":99}]"
            .data(using: .utf8)!, forKey: "ClaudeUsageBarHistory")

        let store2 = UsageHistoryStore(fileURL: url, userDefaults: defaults)
        XCTAssertEqual(store2.records.count, 1, "Existing file wins; no re-migration")
        XCTAssertEqual(store2.records[0].fiveHourUtilization, 50)
    }

    func testCorruptFileStartsEmpty() throws {
        let url = tempFileURL()
        try "not json".data(using: .utf8)!.write(to: url)
        let store = UsageHistoryStore(fileURL: url, userDefaults: ephemeralDefaults())
        XCTAssertEqual(store.records.count, 0, "Corrupt file must not crash; start empty")
    }

    func testAppendSnapshotMapsFields() {
        let store = UsageHistoryStore(fileURL: tempFileURL(), userDefaults: ephemeralDefaults())
        let timestamp = Date()
        let snapshot = UsageSnapshot(
            fiveHourUtilization: 33, sevenDayUtilization: 44, sonnetUtilization: 55,
            fiveHourResetIn: nil, sevenDayResetIn: nil,
            fiveHourResetsAt: nil, sevenDayResetsAt: nil,
            lastUpdated: timestamp
        )
        store.append(snapshot: snapshot)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records[0].fiveHourUtilization, 33)
        XCTAssertEqual(store.records[0].sevenDayUtilization, 44)
        XCTAssertEqual(store.records[0].sonnetUtilization, 55)
        XCTAssertEqual(store.records[0].timestamp, timestamp)
    }
}
