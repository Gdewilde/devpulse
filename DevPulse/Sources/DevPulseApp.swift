import SwiftUI
import AppKit
import UserNotifications

// MARK: - App Entry Point

@main
struct DevPulseEntry {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var refreshTimer: Timer?
    private let appState = AppState()
    private let ramAdvisor = RAMAdvisor()
    private var lastSnapshotTime: Date = .distantPast
    private var reportPanel: NSPanel?
    private var eventMonitor: Any?
    private let autoOptimizer = AutoOptimizer()
    private let timelineStore = TimelineStore()
    private let swapTracker = SwapTracker()
    private var previousZombiePids: Set<Int32> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 520)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(state: appState, onAction: { [weak self] action in
                self?.handleAction(action)
            })
        )

        // Status bar button
        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        updateStatusBar()
        refreshData()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.appState.stats = MemoryStats.current()
            self?.appState.updateSwapTrend()
            self?.swapTracker.record(swapGB: self?.appState.stats.swapUsedGB ?? 0)
            self?.updateStatusBar()
            self?.refreshData()
        }

        // Start auto-optimizer
        autoOptimizer.appState = appState
        autoOptimizer.start()

        // Fetch SSD health once (slow operation)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let health = getSSDHealth()
            DispatchQueue.main.async { self?.appState.ssdHealth = health }
        }

        // Global hotkey: Cmd+Shift+M for RAM Report
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.command, .shift]) && event.charactersIgnoringModifiers == "m" {
                DispatchQueue.main.async { self?.showRAMReport() }
            }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.command, .shift]) && event.charactersIgnoringModifiers == "m" {
                DispatchQueue.main.async { self?.showRAMReport() }
                return nil
            }
            return event
        }
    }

    // MARK: - Status Bar

    private func updateStatusBar() {
        guard let button = statusItem.button else { return }
        let stats = appState.stats

        let symbolName = stats.status.icon
        let tint: NSColor
        switch stats.status {
        case .healthy:  tint = .systemGreen
        case .warning:  tint = .systemOrange
        case .critical: tint = .systemRed
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: stats.status.label) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            let configured = image.withSymbolConfiguration(config) ?? image
            configured.isTemplate = false
            let colored = configured.copy() as! NSImage
            colored.lockFocus()
            tint.set()
            NSRect(origin: .zero, size: colored.size).fill(using: .sourceAtop)
            colored.unlockFocus()
            button.image = colored
            button.imagePosition = .imageLeading
        }

        let swapSuffix = appState.swapTrend == .stable ? "" : " \(appState.swapTrend.rawValue)"
        button.title = " \(Int(stats.usedPercent))%\(swapSuffix)"
        button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    }

    // MARK: - Data Refresh

    private func refreshData() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let procs = getTopProcesses(limit: 8)
            let zombies = getZombieProcesses()
            let docker = getDockerStats()
            let electron = getElectronStats(processes: procs)
            let chrome = getChromeStats()
            let inactive = getInactiveDevServers()
            let stats = self.appState.stats

            DispatchQueue.main.async {
                self.appState.processes = procs
                self.appState.zombies = zombies
                self.notifyNewZombies(zombies)
                self.appState.dockerStats = docker
                self.appState.electronStats = electron
                self.appState.chromeStats = chrome
                self.appState.inactiveServers = inactive

                // Record snapshot every 60s
                if Date().timeIntervalSince(self.lastSnapshotTime) >= 60 {
                    let zombieMB = zombies.reduce(0) { $0 + $1.totalMB }
                    let dockerWasteMB = docker?.wasteMB ?? 0
                    let electronWasteMB = electron?.duplicateWasteMB ?? 0
                    let inactiveMB = inactive.reduce(0) { $0 + $1.totalMB }
                    self.ramAdvisor.recordSnapshot(
                        stats: stats,
                        zombieMB: zombieMB,
                        dockerWasteMB: dockerWasteMB,
                        electronWasteMB: electronWasteMB,
                        inactiveServerMB: inactiveMB
                    )
                    self.lastSnapshotTime = Date()

                    // Timeline: record snapshot and detect events
                    self.timelineStore.recordSnapshot(stats: stats, topProcess: procs.first)
                    self.timelineStore.detectEvents(stats: stats, dockerRunning: docker?.isRunning ?? false)
                }

                self.appState.verdict = self.ramAdvisor.getVerdict()
                self.appState.modelResults = self.ramAdvisor.checkModels()

                // Scan cleanups periodically (every 5 min, piggyback on snapshot timing)
                if Date().timeIntervalSince(self.lastSnapshotTime) < 2 {
                    DispatchQueue.global(qos: .utility).async { [weak self] in
                        let scan = scanAllCleanups()
                        DispatchQueue.main.async {
                            self?.appState.cleanupScan = scan
                        }
                    }
                }
            }
        }
    }

    // MARK: - Zombie Notifications

    private func notifyNewZombies(_ zombies: [ZombieGroup]) {
        let currentPids = Set(zombies.flatMap(\.pids))
        let newPids = currentPids.subtracting(previousZombiePids)
        previousZombiePids = currentPids

        guard !newPids.isEmpty else { return }

        // Find the groups that contain new pids
        let newGroups = zombies.filter { group in
            group.pids.contains { newPids.contains($0) }
        }
        let newCount = newPids.count
        let newMB = newGroups.reduce(0) { $0 + $1.totalMB }
        let memStr = newMB >= 1024
            ? String(format: "%.1f GB", Double(newMB) / 1024)
            : "\(newMB) MB"

        // Build description
        var parts: [String] = []
        let orphanCount = newGroups.filter { $0.kind == .orphan }.reduce(0) { $0 + $1.count }
        let lspCount = newGroups.filter { $0.kind == .staleLSP }.reduce(0) { $0 + $1.count }
        let watcherCount = newGroups.filter { $0.kind == .staleWatcher }.reduce(0) { $0 + $1.count }
        if orphanCount > 0 { parts.append("\(orphanCount) orphaned") }
        if lspCount > 0 { parts.append("\(lspCount) stale LSP") }
        if watcherCount > 0 { parts.append("\(watcherCount) stale watcher") }
        let detail = parts.joined(separator: ", ")

        let projects = Set(newGroups.map(\.project)).joined(separator: ", ")

        let content = UNMutableNotificationContent()
        content.title = "\(newCount) zombie processes using \(memStr)"
        content.body = "\(detail) from \(projects). Open DevPulse to kill them."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "devpulse-zombie-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Action Handler

    private func handleAction(_ action: AppAction) {
        switch action {
        case .quit(let proc):
            guard let bundleName = proc.appBundleName else { return }
            popover.performClose(nil)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let script = "tell application \"\(bundleName)\" to quit"
                let osa = Process()
                osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                osa.arguments = ["-e", script]
                try? osa.run()
                osa.waitUntilExit()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.refreshData() }
            }

        case .forceQuit(let proc):
            popover.performClose(nil)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                for pid in proc.pids { kill(pid, SIGKILL) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.refreshData() }
            }

        case .killPids(let pids):
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                for pid in pids { kill(pid, SIGTERM) }
                Thread.sleep(forTimeInterval: 2)
                for pid in pids { kill(pid, SIGKILL) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.refreshData() }
            }

        case .showReport:
            popover.performClose(nil)
            showRAMReport()

        case .showTimeline:
            popover.performClose(nil)
            showTimelinePanel()

        case .fullCheck:
            popover.performClose(nil)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", "Terminal", "/Users/gj/Apps/devpulse/mem-check.sh"]
            try? p.run()

        case .autoFix:
            popover.performClose(nil)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", "Terminal", "/Users/gj/Apps/devpulse/mem-check.sh", "--args", "--fix"]
            try? p.run()

        case .restartDockerVM:
            restartDockerVM { [weak self] success, message in
                if success { self?.refreshData() }
            }

        case .quickClean:
            appState.isCleaningUp = true
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let result = runQuickClean()
                DispatchQueue.main.async {
                    self?.appState.lastCleanupResult = result
                    self?.appState.isCleaningUp = false
                    self?.refreshData()
                }
            }

        case .toggleAutoOptimizer:
            appState.autoOptimizerEnabled.toggle()
            if appState.autoOptimizerEnabled {
                autoOptimizer.start()
            } else {
                autoOptimizer.stop()
            }

        case .openURL(let urlString):
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }

        case .chromeTaskManager:
            popover.performClose(nil)
            DispatchQueue.global(qos: .userInitiated).async {
                let script = """
                tell application "Google Chrome" to activate
                delay 0.3
                tell application "System Events"
                    key code 53 using shift down
                end tell
                """
                let osa = Process()
                osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                osa.arguments = ["-e", script]
                try? osa.run()
                osa.waitUntilExit()
            }

        case .chromeMemorySaver:
            popover.performClose(nil)
            DispatchQueue.global(qos: .userInitiated).async {
                let script = """
                tell application "Google Chrome"
                    activate
                    open location "chrome://settings/performance"
                end tell
                """
                let osa = Process()
                osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                osa.arguments = ["-e", script]
                try? osa.run()
                osa.waitUntilExit()
            }

        case .quitApp:
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Timeline Panel

    private var timelinePanel: NSPanel?

    private func showTimelinePanel() {
        if let existing = timelinePanel {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "DevPulse Memory Timeline"
        panel.isFloatingPanel = true
        panel.center()

        let scrollView = NSScrollView(frame: panel.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.backgroundColor = .textBackgroundColor
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        let timelineText = timelineStore.exportAsText(hours: 24)
        textView.string = timelineText

        scrollView.documentView = textView
        panel.contentView = scrollView
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        timelinePanel = panel
    }

    // MARK: - RAM Report Panel

    @objc private func showRAMReport() {
        if let existing = reportPanel {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "DevPulse RAM Report"
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.center()

        let scrollView = NSScrollView(frame: panel.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.backgroundColor = .textBackgroundColor

        let report = buildReportText()
        textView.textStorage?.setAttributedString(report)

        scrollView.documentView = textView
        panel.contentView = scrollView

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        reportPanel = panel
    }

    private func buildReportText() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let stats = appState.stats

        func heading(_ text: String) {
            result.append(NSAttributedString(string: "\(text)\n", attributes: [
                .font: NSFont.systemFont(ofSize: 20, weight: .bold),
                .foregroundColor: NSColor.labelColor
            ]))
        }
        func subheading(_ text: String) {
            result.append(NSAttributedString(string: "\n\(text)\n", attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]))
        }
        func body(_ text: String) {
            result.append(NSAttributedString(string: "\(text)\n", attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor
            ]))
        }
        func mono(_ text: String) {
            result.append(NSAttributedString(string: "\(text)\n", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.labelColor
            ]))
        }

        heading("RAM Report")
        body("Generated \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))")

        subheading("System Memory")
        mono("\(String(format: "%.0f", stats.usedGB)) / \(String(format: "%.0f", stats.totalGB)) GB used (\(Int(stats.usedPercent))%)")
        mono("Free: \(String(format: "%.1f", stats.freeGB)) GB  Compressed: \(String(format: "%.1f", stats.compressedGB)) GB  Swap: \(String(format: "%.1f", stats.swapUsedGB)) GB")

        if let verdict = appState.verdict {
            subheading("Verdict: \(verdict.headline)")
            body(verdict.detail)

            let w = verdict.waste
            if w.totalMB > 0 {
                subheading("Waste Breakdown")
                if w.zombieMB > 0 { mono("  Zombie processes:     \(w.zombieMB) MB") }
                if w.dockerMB > 0 { mono("  Docker overhead:      \(w.dockerMB) MB") }
                if w.electronMB > 0 { mono("  Electron duplicates:  \(w.electronMB) MB") }
                if w.inactiveServerMB > 0 { mono("  Idle dev servers:     \(w.inactiveServerMB) MB") }
                mono("  Total reclaimable:    \(w.totalMB) MB")
            }
        }

        subheading("Top Processes")
        for proc in appState.processes {
            mono("  \(proc.displayName.padding(toLength: 24, withPad: " ", startingAt: 0)) \(proc.memoryFormatted)")
        }

        if !appState.modelResults.isEmpty {
            subheading("Can I Run? — Local AI Models")
            for r in appState.modelResults.prefix(15) {
                let icon: String
                switch r.feasibility {
                case .runsGreat:   icon = "+"
                case .runsOk:      icon = "~"
                case .afterCleanup: icon = "o"
                case .tooHeavy:    icon = "x"
                }
                let ramGB = r.bestQuant.ramRequiredMB / 1024
                mono("  \(icon) \(r.model.name.padding(toLength: 22, withPad: " ", startingAt: 0)) \(r.bestQuant.level.padding(toLength: 8, withPad: " ", startingAt: 0)) \(ramGB) GB")
            }
        }

        return result
    }
}
