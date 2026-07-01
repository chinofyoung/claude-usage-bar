# Phase 1 — Data Foundation Design

**Date:** 2026-06-30
**Status:** Approved (pending user spec review)
**App:** ClaudeUsageBar (macOS menu bar app, AppKit + SwiftUI, macOS 13+, SPM, no third-party deps)

## Context

ClaudeUsageBar polls `https://api.anthropic.com/api/oauth/usage` and displays 5h / 7d / Sonnet
utilization. History is currently stored in `UserDefaults` (key `ClaudeUsageBarHistory`, up to 288
records ≈ 24h) and rendered as 24h sparklines.

This is the first of four phases. It builds the data layer that later phases (charts, export-driven
features) read from. The three deliverables: **file-based 30-day history**, a **forecasting engine**,
and **CSV export**.

Decisions already made: phased build in order; multi-account cut; 30 days retention in a file;
long-range chart (Phase 2) will be expandable in the popover.

## Goals

1. Persist usage history in a JSON file under Application Support, retaining 30 days.
2. Migrate existing UserDefaults history into the file on first launch, then stop using UserDefaults
   for history.
3. Provide a pure, unit-tested forecasting engine that estimates time-to-limit per metric.
4. Show a forecast line per metric in the popover.
5. Export full history to CSV via `NSSavePanel`.

## Non-Goals (Phase 1)

- No menu-bar/status-bar forecast text (popover only).
- No charts beyond the existing sparklines (that is Phase 2).
- No JSON export (CSV only).
- No multi-account support (cut).

## Components

### 1. `UsageHistoryStore` (modify existing)

Keep the public surface stable: it still exposes the `@Published` array of records and an
`append`/record method consumed by SwiftUI and the polling service. Only the persistence backend
changes.

- **Storage location:** `~/Library/Application Support/ClaudeUsageBar/history.json`.
  Create the directory if missing.
- **Retention:** 30 days. On append, drop records with `timestamp` older than `now − 30 days`.
- **Write strategy:** atomic writes (`Data.write(to:options:.atomic)`). **Implementation decision
  (post-review):** we write on every `append` rather than coalescing/debouncing. The only production
  caller (`UsageService`) appends once per poll cycle (≥60s apart), so a per-append full-file write
  is at most one write per minute — no throttle needed — and writing every append is strictly safer
  for durability (it removes open risk #2, losing the final write). The earlier "throttle" wording
  is superseded by this choice.
- **Load:** on init, read and decode the file; tolerate a missing or corrupt file by starting empty
  (log, don't crash).
- **Record shape:** extends today's `UsageHistoryRecord`. Today it is
  `timestamp: Date`, `fiveHourUtilization: Int`, `sevenDayUtilization: Int`. Phase 1 adds
  `sonnetUtilization: Int?` (declared Optional so old records decode with nil). Values stay `Int`
  (0–100) to match the existing codebase and `UsageSnapshot`; the forecaster casts to `Double`
  internally. No field is renamed (sparklines reference `\.fiveHourUtilization` / `\.sevenDayUtilization`).

#### Migration (one-time)

On first launch after upgrade:
1. If `history.json` does not exist and the UserDefaults `ClaudeUsageBarHistory` key has records,
   decode those records and write them to `history.json`.
2. Remove the UserDefaults key after a successful file write.
3. If the file already exists, do nothing (migration already happened).

### 2. `UsageForecaster` (new, pure)

A dependency-free struct. No UI, no network, no I/O — input records, output a forecast. This makes
it directly unit-testable.

```
struct Forecast {
    enum Trend { case rising, steady, declining }
    let trend: Trend
    let timeToLimit: TimeInterval?   // nil unless rising and limit reached before reset
    let projectedAtReset: Double?    // utilization % projected at resetsAt, when known
}

enum UsageForecaster {
    static func forecast(
        records: [UsageHistoryRecord],
        metric: KeyPath<UsageHistoryRecord, Double>,  // or a small Metric enum
        current: Double,
        resetsAt: Date?,
        now: Date,
        window: TimeInterval = 3600   // trailing window, default 60 min
    ) -> Forecast
}
```

**Algorithm:**
1. Take records within the trailing `window` ending at `now`. Need ≥ 2 points; otherwise return
   `.steady` with nil ETA (insufficient data).
2. Compute slope of utilization vs time (simple least-squares or first-vs-last slope) in %/sec.
3. If `slope <= ~0` (within a small epsilon) → `.steady` (or `.declining` if clearly negative),
   `timeToLimit = nil`.
4. If `slope > 0`:
   - `timeToLimit = (100 − current) / slope`.
   - If `resetsAt` is known and the reset occurs before `now + timeToLimit`, set `timeToLimit = nil`
     and compute `projectedAtReset = current + slope * (resetsAt − now)` (clamped to ≤ 100). Trend
     stays `.rising`. This expresses "you'll reset before you hit the cap."

The function is deterministic given `now` (injected, never `Date()` internally) so tests are stable.

**`resetsAt` source:** `UsageSnapshot` today keeps reset times only as preformatted strings
(`fiveHourResetIn` / `sevenDayResetIn`) and discards the parsed `Date`. Phase 1 adds
`fiveHourResetsAt: Date?` and `sevenDayResetsAt: Date?` to `UsageSnapshot`, populated in
`UsageSnapshot.from(response:)` from the same ISO8601 parse already happening there, so the popover
can pass a real `Date` to the forecaster. Sonnet has no reset time in the API, so its forecast
passes `resetsAt: nil`.

### 3. Popover forecast display (`PopoverView`)

Under each metric's existing reset countdown, add one small secondary-text line:
- Rising, hits limit first: `"≈ 2h 40m to limit"`.
- Rising, resets first: `"resets first — on pace to ~78%"`.
- Steady: `"steady"`.
- Declining: `"declining"`.
- Insufficient data: omit the line (or `"—"`).

Pull records from `UsageHistoryStore`, current value + `resetsAt` from the current `UsageSnapshot`.
Keep styling consistent with existing secondary text (caption font, secondary color).

### 4. CSV export

- A "Export History…" button in the popover's action area (near Refresh).
- Opens `NSSavePanel`, default filename `claude-usage-history.csv`.
- Writes a header row + one row per record:
  `timestamp_iso8601,five_hour,seven_day,seven_day_sonnet`.
  Empty field for nil Sonnet values.
- Sorted ascending by timestamp.

## Data Flow

```
UsageService (poll) ──► UsageSnapshot ──► UsageHistoryStore.append(record)
                                              │  (throttled atomic write to history.json)
                                              ▼
PopoverView ◄── @Published records ◄── UsageHistoryStore
     │
     ├─ sparkline (existing)
     ├─ UsageForecaster.forecast(records, …) ──► forecast line (new)
     └─ Export… ──► NSSavePanel ──► CSV string from records
```

## Error Handling

- Missing/corrupt history file → start empty, log, continue.
- App Support directory creation failure → fall back to in-memory only for the session, log.
- Export write failure → present an `NSAlert` with the error; do not crash.
- Forecaster never throws; insufficient/degenerate data → `.steady`, nil ETA.

## Testing

Pure-logic unit tests (XCTest, SPM test target):

**`UsageForecaster`:**
- Rising linearly → correct `timeToLimit`, trend `.rising`.
- Flat → `.steady`, nil ETA.
- Declining → `.declining`, nil ETA.
- Rising but `resetsAt` before projected limit → nil `timeToLimit`, `projectedAtReset` set, trend
  `.rising`.
- < 2 points in window → `.steady`, nil ETA.
- `now` injected so results are deterministic.

**`UsageHistoryStore`:**
- 30-day trim drops old records on append, keeps recent.
- Migration: UserDefaults records present + no file → file written, UserDefaults key cleared.
- Migration no-ops when file already exists.
- Corrupt file → starts empty without crashing.
- (Use a temp directory / injected file URL so tests don't touch the real Application Support path.)

## Open Risks

- `UsageHistoryStore` may need a small refactor to inject the file URL (for tests) — keep this
  targeted, don't refactor unrelated code.
- Throttled writes must still flush a final write so data isn't lost between poll cycles; ensure a
  write happens per append (coalescing only rapid bursts, which polling won't normally produce).
