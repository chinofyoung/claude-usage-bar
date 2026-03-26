import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var settingsManager = SettingsManager.shared
    var onClose: () -> Void = {}

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.green)
                    Text("Claude Code OAuth")
                    Spacer()
                    Text("Auto")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.green)
                }
            } header: {
                Text("Authentication")
            }

            Section {
                Toggle("Launch at login", isOn: $settingsManager.settings.launchAtLogin)
                    .onChange(of: settingsManager.settings.launchAtLogin) { newValue in
                        settingsManager.save()
                        updateLaunchAtLogin(enabled: newValue)
                    }
            } header: {
                Text("General")
            }

            // MARK: Appearance — Status Bar subsection
            Section {
                Picker("Style", selection: $settingsManager.settings.statusBarStyle) {
                    ForEach(StatusBarStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settingsManager.settings.statusBarStyle) { _ in
                    settingsManager.save()
                }

                Toggle("Show 5-hour metric", isOn: $settingsManager.settings.showFiveHour)
                    .onChange(of: settingsManager.settings.showFiveHour) { _ in
                        settingsManager.save()
                    }

                Toggle("Show 7-day metric", isOn: $settingsManager.settings.showSevenDay)
                    .onChange(of: settingsManager.settings.showSevenDay) { _ in
                        settingsManager.save()
                    }

                Toggle("Show Sonnet metric", isOn: $settingsManager.settings.showSonnet)
                    .onChange(of: settingsManager.settings.showSonnet) { _ in
                        settingsManager.save()
                    }

                Toggle("Use icons", isOn: $settingsManager.settings.useIcons)
                    .disabled(settingsManager.settings.statusBarStyle != .normal)
                    .onChange(of: settingsManager.settings.useIcons) { _ in
                        settingsManager.save()
                    }
            } header: {
                Text("Status Bar")
            }

            // MARK: Appearance — Popover subsection
            Section {
                Picker("Width", selection: $settingsManager.settings.popoverWidth) {
                    ForEach(PopoverWidth.allCases, id: \.self) { width in
                        Text(width.rawValue).tag(width)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settingsManager.settings.popoverWidth) { _ in
                    settingsManager.save()
                }

                Picker("Progress bar height", selection: $settingsManager.settings.progressBarHeight) {
                    ForEach(ProgressBarHeight.allCases, id: \.self) { height in
                        Text(height.rawValue).tag(height)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settingsManager.settings.progressBarHeight) { _ in
                    settingsManager.save()
                }

                Toggle("Show sparkline charts", isOn: $settingsManager.settings.showSparklines)
                    .onChange(of: settingsManager.settings.showSparklines) { _ in
                        settingsManager.save()
                    }

                Picker("Accent color", selection: $settingsManager.settings.accentColor) {
                    ForEach(AccentColorOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .onChange(of: settingsManager.settings.accentColor) { _ in
                    settingsManager.save()
                }
            } header: {
                Text("Popover")
            }

            Section {
                Picker("Refresh every", selection: $settingsManager.settings.pollInterval) {
                    Text("1 minute").tag(TimeInterval(60))
                    Text("2 minutes").tag(TimeInterval(120))
                    Text("5 minutes").tag(TimeInterval(300))
                    Text("10 minutes").tag(TimeInterval(600))
                    Text("15 minutes").tag(TimeInterval(900))
                }
                .onChange(of: settingsManager.settings.pollInterval) { _ in
                    settingsManager.save()
                }
            } header: {
                Text("Polling")
            }

            Section {
                Toggle("Enable notifications", isOn: $settingsManager.settings.notificationsEnabled)
                    .onChange(of: settingsManager.settings.notificationsEnabled) { _ in
                        settingsManager.save()
                    }

                if settingsManager.settings.notificationsEnabled {
                    LabeledContent {
                        Text("\(Int(settingsManager.settings.warningThreshold))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.orange)
                                .frame(width: 8, height: 8)
                            Text("Warning")
                        }
                    }
                    Slider(
                        value: $settingsManager.settings.warningThreshold,
                        in: 50...95,
                        step: 5
                    )
                    .onChange(of: settingsManager.settings.warningThreshold) { _ in
                        settingsManager.save()
                    }

                    LabeledContent {
                        Text("\(Int(settingsManager.settings.criticalThreshold))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                            Text("Critical")
                        }
                    }
                    Slider(
                        value: $settingsManager.settings.criticalThreshold,
                        in: 60...100,
                        step: 5
                    )
                    .onChange(of: settingsManager.settings.criticalThreshold) { _ in
                        settingsManager.save()
                    }
                }
            } header: {
                Text("Notifications")
            }

            Section {
                HStack {
                    Button("Reset to Defaults", role: .destructive) {
                        settingsManager.resetToDefaults()
                    }
                    Spacer()
                    Button("Close") {
                        onClose()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.visible)
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            settingsManager.settings.launchAtLogin = !enabled
            settingsManager.save()
        }
    }
}
