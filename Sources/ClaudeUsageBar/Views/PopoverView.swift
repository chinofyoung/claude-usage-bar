import SwiftUI

// MARK: - AccentColorOption + SwiftUI / AppKit helpers

extension AccentColorOption {
    var color: Color {
        switch self {
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .teal: return .teal
        case .system: return .accentColor
        }
    }

    var nsColor: NSColor {
        switch self {
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .teal: return .systemTeal
        case .system: return .controlAccentColor
        }
    }
}

// MARK: - PopoverView

struct PopoverView: View {
    @ObservedObject var usageService = UsageService.shared
    @ObservedObject var settingsManager = SettingsManager.shared
    @ObservedObject var historyStore = UsageHistoryStore.shared

    var body: some View {
        let settings = settingsManager.settings
        VStack(alignment: .leading, spacing: 12) {
            headerView

            if usageService.isLoading && usageService.currentUsage == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if let errorMessage = usageService.error, usageService.currentUsage == nil {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if let usage = usageService.currentUsage {
                usageRows(for: usage)
            }

            if settings.showSparklines && historyStore.last24Hours.count >= 2 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("24h trend")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("5h")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            SparklineView(
                                records: historyStore.last24Hours,
                                keyPath: \.fiveHourUtilization,
                                color: .blue,
                                label: "5h"
                            )
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("7d")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            SparklineView(
                                records: historyStore.last24Hours,
                                keyPath: \.sevenDayUtilization,
                                color: .purple,
                                label: "7d"
                            )
                        }
                    }
                    .frame(height: 40)
                }
            }

            Divider()

            actionButtons

            settingsButton

            Divider()

            quitButton
        }
        .padding(16)
        .frame(width: settings.popoverWidth.points)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .cornerRadius(10)
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            Text("Claude Usage")
                .font(.headline)
            Spacer()
            if let usage = usageService.currentUsage {
                Text(relativeTime(from: usage.lastUpdated))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func usageRows(for usage: UsageSnapshot) -> some View {
        let settings = settingsManager.settings
        return VStack(spacing: 8) {
            if settings.showFiveHour {
                UsageRowView(
                    iconName: "clock",
                    label: "5-hour",
                    utilization: usage.fiveHourUtilization,
                    resetIn: usage.fiveHourResetIn,
                    warningThreshold: settings.warningThreshold,
                    criticalThreshold: settings.criticalThreshold,
                    useIcons: settings.useIcons,
                    progressBarHeight: settings.progressBarHeight.points,
                    accentColor: settings.accentColor.color
                )
            }
            if settings.showSevenDay {
                UsageRowView(
                    iconName: "calendar",
                    label: "7-day",
                    utilization: usage.sevenDayUtilization,
                    resetIn: usage.sevenDayResetIn,
                    warningThreshold: settings.warningThreshold,
                    criticalThreshold: settings.criticalThreshold,
                    useIcons: settings.useIcons,
                    progressBarHeight: settings.progressBarHeight.points,
                    accentColor: settings.accentColor.color
                )
            }
            if settings.showSonnet, let sonnet = usage.sonnetUtilization {
                UsageRowView(
                    iconName: "sparkles",
                    label: "Sonnet",
                    utilization: sonnet,
                    resetIn: nil,
                    warningThreshold: settings.warningThreshold,
                    criticalThreshold: settings.criticalThreshold,
                    useIcons: settings.useIcons,
                    progressBarHeight: settings.progressBarHeight.points,
                    accentColor: settings.accentColor.color
                )
            }
        }
    }

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

            Button {
                Task { await usageService.fetchUsage() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
        }
    }

    private var settingsButton: some View {
        Button {
            AppDelegate.shared.openSettings()
        } label: {
            HStack {
                Image(systemName: "gear")
                Text("Settings")
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
    }

    private var quitButton: some View {
        Button {
            NSApp.terminate(nil)
        } label: {
            HStack {
                Image(systemName: "power")
                Text("Quit")
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundColor(.secondary)
    }

    // MARK: - Helpers

    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - UsageRowView

private struct UsageRowView: View {
    let iconName: String
    let label: String
    let utilization: Int
    let resetIn: String?
    let warningThreshold: Double
    let criticalThreshold: Double
    let useIcons: Bool
    let progressBarHeight: CGFloat
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 6) {
                if useIcons {
                    Image(systemName: iconName)
                        .font(.caption)
                        .frame(width: 14, alignment: .center)
                        .foregroundColor(utilizationColor)
                }
                Text(label)
                    .font(.caption)
                Spacer()
                Text("\(utilization)%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(utilizationColor)
                    .frame(alignment: .center)
                if let resetIn {
                    Text(resetIn)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            progressBar
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: progressBarHeight)
                    .cornerRadius(progressBarHeight / 2)

                Rectangle()
                    .fill(utilizationColor)
                    .frame(
                        width: geometry.size.width * CGFloat(utilization) / 100.0,
                        height: progressBarHeight
                    )
                    .cornerRadius(progressBarHeight / 2)
            }
        }
        .frame(height: progressBarHeight)
    }

    private var utilizationColor: Color {
        let value = Double(utilization)
        if value >= criticalThreshold {
            return .red
        } else if value >= warningThreshold {
            return .orange
        } else {
            return accentColor
        }
    }
}

// MARK: - VisualEffectView

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
