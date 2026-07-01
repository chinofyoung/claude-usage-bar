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
