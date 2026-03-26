import SwiftUI

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
}
