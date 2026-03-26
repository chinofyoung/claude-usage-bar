import AppKit
import SwiftUI
import Combine
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate!

    private var statusItem: NSStatusItem!
    private var popoverPanel: NSPanel?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⏳"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        // Panel is created on demand in togglePopover()

        UsageService.shared.startPolling()
        NotificationService.shared.requestAuthorization()

        UsageService.shared.$currentUsage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] usage in
                self?.updateStatusBar(usage: usage)
            }
            .store(in: &cancellables)

        UsageService.shared.$currentUsage
            .receive(on: DispatchQueue.main)
            .sink { usage in
                guard let usage else { return }
                NotificationService.shared.checkThresholds(
                    usage: usage,
                    settings: SettingsManager.shared.settings
                )
            }
            .store(in: &cancellables)
    }

    private func updateStatusBar(usage: UsageSnapshot?) {
        guard let usage, let button = statusItem.button else {
            statusItem.button?.title = "⏳"
            return
        }

        let settings = SettingsManager.shared.settings
        let attributedString = NSMutableAttributedString()

        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let baseAttributes: [NSAttributedString.Key: Any] = [.font: font]

        func color(for value: Int) -> NSColor {
            let doubleValue = Double(value)
            if doubleValue >= settings.criticalThreshold {
                return NSColor.systemRed
            } else if doubleValue >= settings.warningThreshold {
                return NSColor.systemOrange
            } else {
                return NSColor.labelColor
            }
        }

        let sevenDayValue = usage.sevenDayUtilization
        let fiveHourValue = usage.fiveHourUtilization
        let sonnetValue = usage.sonnetUtilization

        var allValues = [fiveHourValue, sevenDayValue]
        if let s = sonnetValue { allValues.append(s) }
        let isCritical = allValues.contains { Double($0) >= settings.criticalThreshold }

        let separator = NSAttributedString(
            string: " · ",
            attributes: baseAttributes.merging([.foregroundColor: NSColor.secondaryLabelColor]) { $1 }
        )

        attributedString.append(NSAttributedString(
            string: "5h:\(fiveHourValue)%",
            attributes: baseAttributes.merging([.foregroundColor: color(for: fiveHourValue)]) { $1 }
        ))
        attributedString.append(separator)
        attributedString.append(NSAttributedString(
            string: "7d:\(sevenDayValue)%",
            attributes: baseAttributes.merging([.foregroundColor: color(for: sevenDayValue)]) { $1 }
        ))
        if let sonnetValue {
            attributedString.append(NSAttributedString(string: separator.string, attributes: separator.attributes(at: 0, effectiveRange: nil)))
            attributedString.append(NSAttributedString(
                string: "S:\(sonnetValue)%",
                attributes: baseAttributes.merging([.foregroundColor: color(for: sonnetValue)]) { $1 }
            ))
        }

        if isCritical {
            let warning = NSAttributedString(string: "⚠️ ", attributes: baseAttributes)
            attributedString.insert(warning, at: 0)
        }

        button.attributedTitle = attributedString
    }

    @objc private func togglePopover() {
        if let panel = popoverPanel, panel.isVisible {
            closePopoverPanel()
        } else if let button = statusItem.button {
            showPopoverPanel(relativeTo: button)
        }
    }

    private func showPopoverPanel(relativeTo button: NSStatusBarButton) {
        let hostingController = NSHostingController(rootView: PopoverView())
        hostingController.view.frame.size = hostingController.sizeThatFits(in: NSSize(width: 260, height: 600))

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hostingController.view.frame.size),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        // Apply rounded corners via the content view
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 10
        panel.contentView?.layer?.masksToBounds = true

        // Position flush below the menu bar button
        let buttonRect = button.window!.convertToScreen(button.convert(button.bounds, to: nil))
        let panelSize = panel.frame.size
        let x = buttonRect.midX - panelSize.width / 2
        let y = buttonRect.minY - panelSize.height
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        panel.orderFrontRegardless()
        self.popoverPanel = panel

        // Close when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopoverPanel()
        }
    }

    private func closePopoverPanel() {
        popoverPanel?.close()
        popoverPanel = nil
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func openSettings() {
        // Close the popover so it doesn't stay behind the window
        closePopoverPanel()

        // If window already exists, just bring it forward
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(onClose: { [weak self] in
            self?.settingsWindow?.close()
        })

        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "ClaudeUsageBar Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 500, height: 600))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        // Temporarily show in Dock so the window behaves like a normal app window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        self.settingsWindow = window

        // Watch for window close to revert to accessory (menu-bar-only) mode
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.settingsWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
