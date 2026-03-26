import SwiftUI

// MARK: - PopoverView

struct PopoverView: View {
    @ObservedObject var usageService = UsageService.shared

    var body: some View {
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

            Divider()

            actionButtons

            settingsButton

            Divider()

            quitButton
        }
        .padding(16)
        .frame(width: 240)
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
        let settings = SettingsManager.shared.settings
        return VStack(spacing: 8) {
            UsageRowView(
                label: "5-hour",
                utilization: usage.fiveHourUtilization,
                resetIn: usage.fiveHourResetIn,
                warningThreshold: settings.warningThreshold,
                criticalThreshold: settings.criticalThreshold
            )
            UsageRowView(
                label: "7-day",
                utilization: usage.sevenDayUtilization,
                resetIn: usage.sevenDayResetIn,
                warningThreshold: settings.warningThreshold,
                criticalThreshold: settings.criticalThreshold
            )
            if let sonnet = usage.sonnetUtilization {
                UsageRowView(
                    label: "Sonnet",
                    utilization: sonnet,
                    resetIn: nil,
                    warningThreshold: settings.warningThreshold,
                    criticalThreshold: settings.criticalThreshold
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
    let label: String
    let utilization: Int
    let resetIn: String?
    let warningThreshold: Double
    let criticalThreshold: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text("\(utilization)%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(utilizationColor)
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
                    .frame(height: 4)
                    .cornerRadius(2)

                Rectangle()
                    .fill(utilizationColor)
                    .frame(
                        width: geometry.size.width * CGFloat(utilization) / 100.0,
                        height: 4
                    )
                    .cornerRadius(2)
            }
        }
        .frame(height: 4)
    }

    private var utilizationColor: Color {
        let value = Double(utilization)
        if value >= criticalThreshold {
            return .red
        } else if value >= warningThreshold {
            return .orange
        } else {
            return .green
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
