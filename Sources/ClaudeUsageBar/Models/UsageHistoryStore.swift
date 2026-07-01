import Foundation
import Combine

struct UsageHistoryRecord: Codable {
    let timestamp: Date
    let fiveHourUtilization: Int
    let sevenDayUtilization: Int
    let sonnetUtilization: Int?
}

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

    nonisolated static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ClaudeUsageBar", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            NSLog("ClaudeUsageBar: failed to create history directory at \(dir.path): \(error)")
        }
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
