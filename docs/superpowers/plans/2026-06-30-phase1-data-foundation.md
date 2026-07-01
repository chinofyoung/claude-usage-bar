# Phase 1 — Data Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give ClaudeUsageBar a durable 30-day usage history, a pure forecasting engine that estimates time-to-limit per metric, a popover forecast line, and CSV export.

**Architecture:** Migrate `UsageHistoryStore` from UserDefaults to an atomic JSON file under Application Support (30-day retention, one-time migration). Add a dependency-free `UsageForecaster` (linear-slope projection over a trailing window, reset-aware) and a `HistoryCSVExporter`. Surface forecasts in `PopoverView` and add an Export button. `UsageSnapshot` gains parsed reset `Date`s so the popover can feed real dates to the forecaster.

**Tech Stack:** Swift 5.9, AppKit + SwiftUI, Combine, XCTest, SPM. No third-party dependencies. macOS 13+.

## Global Constraints

- macOS deployment target: **13.0** (`.macOS(.v13)`). No API newer than macOS 13.
- **No third-party dependencies** — Apple frameworks only.
- **No git state-changing commands** (user policy: no commit/branch/push/etc.). Each task ends at **green tests / successful build**, left staged-but-uncommitted for review. Do NOT run `git commit`.
- Utilization values are `Int` 0–100 throughout (matches existing `UsageSnapshot` / `UsageHistoryRecord`). The forecaster casts to `Double` internally only.
- Never call `Date()` / `Date.now` inside pure logic that needs testing — inject `now`.
- Run unit tests with `swift test`. Build the app with `swift build`.
- Follow existing file conventions: models in `Sources/ClaudeUsageBar/Models/`, services in `Services/`, views in `Views/`, tests in `Tests/ClaudeUsageBarTests/`.

---

### Task 1: Add Sonnet field to `UsageHistoryRecord`

**Files:**
- Modify: `Sources/ClaudeUsageBar/Models/UsageHistoryStore.swift:4-8` (the `UsageHistoryRecord` struct) and `:23-39` (`append`)
- Test: `Tests/ClaudeUsageBarTests/UsageHistoryRecordTests.swift` (create)

**Interfaces:**
- Produces: `UsageHistoryRecord(timestamp: Date, fiveHourUtilization: Int, sevenDayUtilization: Int, sonnetUtilization: Int?)` — Codable; `sonnetUtilization` is Optional so JSON written by the old 2-field struct still decodes (missing key → nil).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ClaudeUsageBarTests/UsageHistoryRecordTests.swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UsageHistoryRecordTests`
Expected: FAIL — `UsageHistoryRecord` has no `sonnetUtilization` argument.

- [ ] **Step 3: Add the field and store it on append**

In `UsageHistoryStore.swift`, replace the struct:

```swift
struct UsageHistoryRecord: Codable {
    let timestamp: Date
    let fiveHourUtilization: Int
    let sevenDayUtilization: Int
    let sonnetUtilization: Int?
}
```

And update the record built in `append(snapshot:)` to pass the snapshot's Sonnet value:

```swift
let record = UsageHistoryRecord(
    timestamp: snapshot.lastUpdated,
    fiveHourUtilization: snapshot.fiveHourUtilization,
    sevenDayUtilization: snapshot.sevenDayUtilization,
    sonnetUtilization: snapshot.sonnetUtilization
)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter UsageHistoryRecordTests`
Expected: PASS (both tests).

- [ ] **Step 5: Verify the whole suite still builds & passes**

Run: `swift test`
Expected: PASS. Leave changes staged for review (no commit — see Global Constraints).

---

### Task 2: File-based 30-day history with migration

**Files:**
- Modify: `Sources/ClaudeUsageBar/Models/UsageHistoryStore.swift` (init, persistence, retention, migration)
- Test: `Tests/ClaudeUsageBarTests/UsageHistoryStoreTests.swift` (create)

**Interfaces:**
- Consumes: `UsageHistoryRecord` from Task 1.
- Produces:
  - `init(fileURL: URL = UsageHistoryStore.defaultFileURL(), userDefaults: UserDefaults = .standard)` — testable; the `.shared` singleton uses defaults.
  - `func append(record: UsageHistoryRecord, now: Date)` — testable core; trims to 30 days using injected `now`.
  - `func append(snapshot: UsageSnapshot)` — delegates to the above with `Date()`.
  - `records: [UsageHistoryRecord]` (`@Published`), `last24Hours` unchanged.
  - File location: `~/Library/Application Support/ClaudeUsageBar/history.json`.

- [ ] **Step 1: Write the failing tests**

```swift
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter UsageHistoryStoreTests`
Expected: FAIL — `init(fileURL:userDefaults:)` / `append(record:now:)` do not exist.

- [ ] **Step 3: Rewrite `UsageHistoryStore` persistence**

Replace the body of `UsageHistoryStore` (keep `UsageHistoryRecord` from Task 1 above it) with:

```swift
@MainActor
final class UsageHistoryStore: ObservableObject {
    static let shared = UsageHistoryStore()

    @Published private(set) var records: [UsageHistoryRecord] = []

    private let fileURL: URL
    private let userDefaults: UserDefaults

    private static let retention: TimeInterval = 30 * 86400
    private static let legacyKey = "ClaudeUsageBarHistory"

    init(fileURL: URL = UsageHistoryStore.defaultFileURL(),
         userDefaults: UserDefaults = .standard) {
        self.fileURL = fileURL
        self.userDefaults = userDefaults
        migrateLegacyIfNeeded()
        records = Self.load(from: fileURL)
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ClaudeUsageBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    func append(snapshot: UsageSnapshot) {
        let record = UsageHistoryRecord(
            timestamp: snapshot.lastUpdated,
            fiveHourUtilization: snapshot.fiveHourUtilization,
            sevenDayUtilization: snapshot.sevenDayUtilization,
            sonnetUtilization: snapshot.sonnetUtilization
        )
        append(record: record, now: Date())
    }

    func append(record: UsageHistoryRecord, now: Date) {
        records.append(record)
        let cutoff = now.addingTimeInterval(-Self.retention)
        records = records.filter { $0.timestamp >= cutoff }
        save()
    }

    var last24Hours: [UsageHistoryRecord] {
        let cutoff = Date().addingTimeInterval(-86400)
        return records.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> [UsageHistoryRecord] {
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([UsageHistoryRecord].self, from: data)
        else { return [] }
        return decoded
    }

    private func migrateLegacyIfNeeded() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard
            let data = userDefaults.data(forKey: Self.legacyKey),
            let decoded = try? JSONDecoder().decode([UsageHistoryRecord].self, from: data),
            !decoded.isEmpty,
            let encoded = try? JSONEncoder().encode(decoded)
        else { return }
        do {
            try encoded.write(to: fileURL, options: .atomic)
            userDefaults.removeObject(forKey: Self.legacyKey)
        } catch {
            // Leave legacy data in place if the write fails; try again next launch.
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter UsageHistoryStoreTests`
Expected: PASS (all five).

- [ ] **Step 5: Full suite + build**

Run: `swift test && swift build`
Expected: PASS / build succeeds. Leave staged for review (no commit).

---

### Task 3: `UsageForecaster` engine

**Files:**
- Create: `Sources/ClaudeUsageBar/Services/UsageForecaster.swift`
- Test: `Tests/ClaudeUsageBarTests/UsageForecasterTests.swift`

**Interfaces:**
- Consumes: `UsageHistoryRecord` (Task 1).
- Produces:
  - `struct UsageForecast { enum Trend { case rising, steady, declining }; let trend: Trend; let timeToLimit: TimeInterval?; let projectedAtReset: Double? }`
  - `enum UsageForecaster { static func forecast(records:value:current:resetsAt:now:window:) -> UsageForecast }` where `value: KeyPath<UsageHistoryRecord, Int>`, `window: TimeInterval = 3600`.

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter UsageForecasterTests`
Expected: FAIL — `UsageForecaster` / `UsageForecast` not defined.

- [ ] **Step 3: Implement the engine**

```swift
// Sources/ClaudeUsageBar/Services/UsageForecaster.swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter UsageForecasterTests`
Expected: PASS (all five).

- [ ] **Step 5: Full suite + build**

Run: `swift test && swift build`
Expected: PASS / succeeds. Leave staged for review.

---

### Task 4: Expose reset `Date`s on `UsageSnapshot`

**Files:**
- Modify: `Sources/ClaudeUsageBar/Models/UsageSnapshot.swift` (struct fields, `from`, `placeholder`, helpers)
- Test: `Tests/ClaudeUsageBarTests/UsageSnapshotTests.swift` (add a case)

**Interfaces:**
- Produces: `UsageSnapshot.fiveHourResetsAt: Date?` and `.sevenDayResetsAt: Date?`, populated from the same ISO8601 strings already parsed for the countdown text.

- [ ] **Step 1: Write the failing test (append to `UsageSnapshotTests`)**

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UsageSnapshotTests/testFromResponse_populatesResetDates`
Expected: FAIL — `fiveHourResetsAt` does not exist.

- [ ] **Step 3: Add the fields and a date-parsing helper**

In `UsageSnapshot.swift`, add two stored properties to the struct (after `sevenDayResetIn`):

```swift
    /// Absolute time the 5-hour window resets, when known.
    let fiveHourResetsAt: Date?
    /// Absolute time the 7-day window resets, when known.
    let sevenDayResetsAt: Date?
```

Add a parsing helper next to `formatCountdown`:

```swift
/// Parses an ISO8601 timestamp into a future `Date`, tolerating fractional seconds.
/// Returns nil if unparseable or already in the past.
private func parseFutureDate(from iso8601: String, relativeTo now: Date) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = formatter.date(from: iso8601)
    if date == nil {
        formatter.formatOptions = [.withInternetDateTime]
        date = formatter.date(from: iso8601)
    }
    guard let date, date > now else { return nil }
    return date
}
```

Update `from(response:)` to populate them:

```swift
        return UsageSnapshot(
            fiveHourUtilization: clamp(response.fiveHour?.utilization),
            sevenDayUtilization: clamp(response.sevenDay?.utilization),
            sonnetUtilization: response.sevenDaySonnet.map { clamp($0.utilization) },
            fiveHourResetIn: response.fiveHour.flatMap { formatCountdown(from: $0.resetsAt, relativeTo: now) },
            sevenDayResetIn: response.sevenDay.flatMap { formatCountdown(from: $0.resetsAt, relativeTo: now) },
            fiveHourResetsAt: response.fiveHour.flatMap { parseFutureDate(from: $0.resetsAt, relativeTo: now) },
            sevenDayResetsAt: response.sevenDay.flatMap { parseFutureDate(from: $0.resetsAt, relativeTo: now) },
            lastUpdated: now
        )
```

Update `placeholder` to pass `fiveHourResetsAt: nil, sevenDayResetsAt: nil`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter UsageSnapshotTests`
Expected: PASS (existing cases + new one).

- [ ] **Step 5: Full suite + build**

Run: `swift test && swift build`
Expected: PASS / succeeds. Leave staged for review.

---

### Task 5: CSV export (exporter + popover button)

**Files:**
- Create: `Sources/ClaudeUsageBar/Services/HistoryCSVExporter.swift`
- Test: `Tests/ClaudeUsageBarTests/HistoryCSVExporterTests.swift`
- Modify: `Sources/ClaudeUsageBar/Views/PopoverView.swift` (add Export button + handler)

**Interfaces:**
- Consumes: `UsageHistoryRecord` (Task 1), `UsageHistoryStore.records` (Task 2).
- Produces: `enum HistoryCSVExporter { static func csv(from records: [UsageHistoryRecord]) -> String }` — header row `timestamp,five_hour,seven_day,seven_day_sonnet`, one row per record sorted ascending, empty field for nil Sonnet, trailing newline.

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HistoryCSVExporterTests`
Expected: FAIL — `HistoryCSVExporter` not defined.

- [ ] **Step 3: Implement the exporter**

```swift
// Sources/ClaudeUsageBar/Services/HistoryCSVExporter.swift
import Foundation

enum HistoryCSVExporter {
    static func csv(from records: [UsageHistoryRecord]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var lines = ["timestamp,five_hour,seven_day,seven_day_sonnet"]
        for r in records.sorted(by: { $0.timestamp < $1.timestamp }) {
            let sonnet = r.sonnetUtilization.map(String.init) ?? ""
            lines.append("\(formatter.string(from: r.timestamp)),\(r.fiveHourUtilization),\(r.sevenDayUtilization),\(sonnet)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HistoryCSVExporterTests`
Expected: PASS (all three).

- [ ] **Step 5: Add the Export button to the popover**

In `PopoverView.swift`, add `import UniformTypeIdentifiers` at the top. Add an export handler method inside `PopoverView`:

```swift
    private func exportHistory() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "claude-usage-history.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let csv = HistoryCSVExporter.csv(from: historyStore.records)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
```

Add an Export button to the `actionButtons` row (between "Open Dashboard" and the refresh button), so it reads:

```swift
    private var actionButtons: some View {
        HStack {
            Button("Open Dashboard") {
                if let url = URL(string: "https://console.anthropic.com/settings/usage") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.caption)

            Spacer()

            Button("Export") { exportHistory() }
                .buttonStyle(.plain)
                .font(.caption)

            Button {
                Task { await usageService.fetchUsage() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
    }
```

- [ ] **Step 6: Build and manually verify**

Run: `swift test && swift build`
Expected: PASS / succeeds.
Manual: launch the app (`make run` or the built binary), open the popover, click **Export**, confirm an `NSSavePanel` appears and writing produces a CSV with a header and rows. Leave staged for review.

---

### Task 6: Forecast line in the popover

**Files:**
- Modify: `Sources/ClaudeUsageBar/Views/PopoverView.swift` (compute forecasts, pass to `UsageRowView`, render line)

**Interfaces:**
- Consumes: `UsageForecaster.forecast(...)` (Task 3), `UsageSnapshot.fiveHourResetsAt/.sevenDayResetsAt` (Task 4), `UsageHistoryStore.records` (Task 2).
- Produces: a per-row secondary forecast line. No new public API; internal to the view.

- [ ] **Step 1: Add a forecast parameter and rendering to `UsageRowView`**

In `PopoverView.swift`, add a stored property to the private `UsageRowView` struct:

```swift
    let forecast: UsageForecast?
```

Add a forecast-text helper and a short-duration formatter inside `UsageRowView`:

```swift
    private func forecastLine(_ f: UsageForecast) -> String? {
        switch f.trend {
        case .steady:    return "steady"
        case .declining: return "declining"
        case .rising:
            if let t = f.timeToLimit { return "≈ \(Self.shortDuration(t)) to limit" }
            if let p = f.projectedAtReset { return "resets first — on pace to ~\(Int(p))%" }
            return "rising"
        }
    }

    private static func shortDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(max(1, m))m"
    }
```

Render the line inside the `UsageRowView` body, just after the `HStack` (the label/percent row) and before `progressBar`:

```swift
            if let forecast, let text = forecastLine(forecast) {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
```

- [ ] **Step 2: Compute and pass forecasts in `usageRows(for:)`**

In `PopoverView.usageRows(for:)`, compute a forecast per metric and pass it to each `UsageRowView`. Add a private helper to `PopoverView`:

```swift
    private func forecast(for value: KeyPath<UsageHistoryRecord, Int>,
                          current: Int, resetsAt: Date?) -> UsageForecast {
        UsageForecaster.forecast(
            records: historyStore.records,
            value: value,
            current: current,
            resetsAt: resetsAt,
            now: Date()
        )
    }
```

Then add `forecast:` to each `UsageRowView(...)` call:
- 5-hour row: `forecast: forecast(for: \.fiveHourUtilization, current: usage.fiveHourUtilization, resetsAt: usage.fiveHourResetsAt)`
- 7-day row: `forecast: forecast(for: \.sevenDayUtilization, current: usage.sevenDayUtilization, resetsAt: usage.sevenDayResetsAt)`
- Sonnet row: `forecast: forecast(for: \.sonnetUtilization, current: sonnet, resetsAt: nil)` — note `\.sonnetUtilization` is `KeyPath<UsageHistoryRecord, Int?>`, which does NOT match the `Int` keypath signature. For Sonnet, pass `forecast: nil` (Sonnet history is Optional and out of scope for forecasting in Phase 1).

So the Sonnet `UsageRowView` gets `forecast: nil`; the 5h and 7d rows get computed forecasts.

- [ ] **Step 3: Build and manually verify**

Run: `swift build`
Expected: build succeeds (watch for keypath type errors — Sonnet must use `forecast: nil`).
Manual: launch the app; after at least two polls (or with migrated history present), confirm the 5-hour and 7-day rows show a secondary line ("steady", "≈ Xh Ym to limit", or "resets first — on pace to ~N%"). With <2 records in the trailing hour the line reads "steady".

- [ ] **Step 4: Full suite + build**

Run: `swift test && swift build`
Expected: PASS / succeeds. Leave staged for review.

---

## Self-Review

- **Spec coverage:** file-based 30-day history + migration (Task 2) ✓; forecasting engine (Task 3) ✓; popover forecast line (Task 6) ✓; CSV export (Task 5) ✓; record/snapshot prerequisites the spec called out — Sonnet field (Task 1), reset `Date`s (Task 4) ✓. Non-goals (no menu-bar forecast, no JSON, no extra charts, no multi-account) respected.
- **Placeholder scan:** no TBD/TODO; every code step shows full code.
- **Type consistency:** `UsageHistoryRecord` 4-field initializer used identically in Tasks 1, 2, 5, 6; `UsageForecaster.forecast(records:value:current:resetsAt:now:window:)` signature matches between Task 3 definition and Task 6 call; `value` keypath is `Int`, so Sonnet (an `Int?` keypath) correctly passes `forecast: nil` rather than calling the forecaster.
- **Scope:** single phase, six right-sized tasks, each independently testable.
