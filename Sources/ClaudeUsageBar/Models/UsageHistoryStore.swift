import Foundation
import Combine

struct UsageHistoryRecord: Codable {
    let timestamp: Date
    let fiveHourUtilization: Int
    let sevenDayUtilization: Int
}

@MainActor
final class UsageHistoryStore: ObservableObject {
    static let shared = UsageHistoryStore()

    @Published private(set) var records: [UsageHistoryRecord] = []

    private static let userDefaultsKey = "ClaudeUsageBarHistory"
    private static let maxEntries = 288

    private init() {
        records = Self.load()
    }

    func append(snapshot: UsageSnapshot) {
        let record = UsageHistoryRecord(
            timestamp: snapshot.lastUpdated,
            fiveHourUtilization: snapshot.fiveHourUtilization,
            sevenDayUtilization: snapshot.sevenDayUtilization
        )
        records.append(record)

        let cutoff = Date().addingTimeInterval(-86400)
        records = records.filter { $0.timestamp >= cutoff }

        if records.count > Self.maxEntries {
            records = Array(records.suffix(Self.maxEntries))
        }

        save()
    }

    var last24Hours: [UsageHistoryRecord] {
        let cutoff = Date().addingTimeInterval(-86400)
        return records.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp < $1.timestamp }
    }

    private func save() {
        guard let encoded = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(encoded, forKey: Self.userDefaultsKey)
    }

    private static func load() -> [UsageHistoryRecord] {
        guard
            let data = UserDefaults.standard.data(forKey: userDefaultsKey),
            let decoded = try? JSONDecoder().decode([UsageHistoryRecord].self, from: data)
        else { return [] }
        return decoded
    }
}
