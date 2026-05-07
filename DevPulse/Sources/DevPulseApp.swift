import SwiftUI
import AppKit
import UserNotifications

// MARK: - App Entry Point

@main
struct DevPulseEntry {
    static func main() {
        // Dual-mode binary: when invoked with a recognized subcommand,
        // dispatch to the CLI and exit before NSApp setup.
        let args = CommandLine.arguments
        if CLI.shouldRun(args: args) {
            exit(CLI.run(args: args))
        }

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
    private let ollamaMonitor = OllamaMonitor()
    private var activePull: OllamaPullManager?
    private var previousZombiePids: Set<Int32> = []
    private var lastStatus: HealthStatus?
    private var lastHeavyCalcTime: Date = .distantPast
    private var lastDiskScanTime: Date = .distantPast
    private let diskScanInterval = PerformanceTuning.diskScanInterval
    private var lastProfileLearningTime: Date = .distantPast
    private let profileLearningInterval = PerformanceTuning.profileLearningInterval

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
        appState.battery = getBatteryStats()
        refreshData()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.appState.stats = MemoryStats.current()
            self?.appState.battery = getBatteryStats()
            self?.appState.updateSwapTrend()
            self?.swapTracker.record(swapGB: self?.appState.stats.swapUsedGB ?? 0)
            self?.updateStatusBar()
            self?.refreshData()
        }

        // Detect local AI runtimes once at launch (presentation-neutral CTAs)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let runtimes = LocalAIRuntimes.detect()
            DispatchQueue.main.async { self?.appState.localAIRuntimes = runtimes }
        }

        // Start auto-optimizer
        autoOptimizer.appState = appState
        autoOptimizer.start()

        // Fetch SSD health once (slow operation)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let health = getSSDHealth()
            DispatchQueue.main.async { self?.appState.ssdHealth = health }
        }

        // Check for updates
        checkForUpdates()

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

        // Only regenerate icon when health status changes
        if stats.status != lastStatus {
            lastStatus = stats.status

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
        }

        let swapSuffix = appState.swapTrend == .stable ? "" : " \(appState.swapTrend.rawValue)"
        button.title = " \(Int(stats.usedPercent))%\(swapSuffix)"
        button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    }

    // MARK: - Data Refresh

    private func refreshData() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            // Gather data in parallel
            let group = DispatchGroup()
            var procs: [ProcessInfo_Memory] = []
            var zombies: [ZombieGroup] = []
            var docker: DockerStats?
            var chrome: ChromeStats?
            var inactive: [InactiveServerGroup] = []
            var gpu: GPUMemoryInfo?
            var ollama: OllamaStatus?

            group.enter()
            DispatchQueue.global(qos: .utility).async {
                procs = getTopProcesses(limit: 8)
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                zombies = getZombieProcesses()
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                docker = getDockerStats()
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                chrome = getChromeStats()
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                inactive = getInactiveDevServers()
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                gpu = getGPUMemoryInfo()
                group.leave()
            }
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                ollama = self.ollamaMonitor.getStatus()
                group.leave()
            }

            group.wait()

            // electron depends on procs
            let electron = getElectronStats(processes: procs)
            let stats = self.appState.stats

            DispatchQueue.main.async {
                if gpu?.allocatedMB != self.appState.gpuMemory?.allocatedMB {
                    self.appState.gpuMemory = gpu
                }
                self.appState.ollamaStatus = ollama
                self.appState.aiMemoryBudget = AIMemoryBudget.calculate(
                    stats: stats, gpu: gpu, ollama: ollama
                )
                self.appState.claudeRouting = ClaudeRoutingDetector.detect()
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

                // Heavy calculations only every 30s
                if Date().timeIntervalSince(self.lastHeavyCalcTime) >= 30 {
                    self.appState.verdict = self.ramAdvisor.getVerdict()
                    self.appState.modelResults = self.ramAdvisor.checkModels()
                    self.appState.appRecommendations = getAppRecommendations(processes: procs)
                    self.lastHeavyCalcTime = Date()
                }

                // Detect current session profile (cheap — just compares running app names)
                self.appState.detectedProfile = self.appState.sessionProfileManager.detectCurrentProfile()

                // Learning: recordSnapshot serializes the full history JSON and writes
                // to disk; detectPatterns is O(n^3) over running apps per snapshot.
                // Throttle to every 5 min and run off main.
                if Date().timeIntervalSince(self.lastProfileLearningTime) >= self.profileLearningInterval {
                    self.lastProfileLearningTime = Date()
                    let manager = self.appState.sessionProfileManager
                    DispatchQueue.global(qos: .utility).async { [weak self] in
                        manager.recordSnapshot()
                        guard manager.learnModeEnabled else { return }
                        let patterns = manager.detectPatterns()
                        DispatchQueue.main.async {
                            self?.appState.learnedPatterns = patterns
                        }
                    }
                }

                // Disk scans (du -sk on node_modules, Ollama models, caches, DerivedData)
                // are expensive — run on first refresh and then every 30 min.
                // Ports are cheaper (lsof) but bundled here so they refresh together.
                if Date().timeIntervalSince(self.lastDiskScanTime) >= self.diskScanInterval {
                    self.lastDiskScanTime = Date()
                    DispatchQueue.global(qos: .utility).async { [weak self] in
                        let scan = scanAllCleanups()
                        let ports = scanListeningPorts()
                        let artifacts = scanDevArtifacts()
                        DispatchQueue.main.async {
                            self?.appState.cleanupScan = scan
                            self?.appState.portScan = ports
                            self?.appState.devArtifactScan = artifacts
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

        case .showBabysitDashboard:
            popover.performClose(nil)
            showBabysitDashboard()

        case .fullCheck:
            popover.performClose(nil)
            if let scriptPath = Bundle.main.path(forResource: "mem-check", ofType: "sh") {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = ["-a", "Terminal", scriptPath]
                try? p.run()
            }

        case .autoFix:
            popover.performClose(nil)
            if let scriptPath = Bundle.main.path(forResource: "mem-check", ofType: "sh") {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = ["-a", "Terminal", scriptPath, "--args", "--fix"]
                try? p.run()
            }

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

        case .copyToClipboard(let text):
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)

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

        case .confirmSwitchProfile(let profile):
            let runningApps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
            let runningNames = Set(runningApps.compactMap { $0.localizedName })
            let profileAppSet = Set(profile.apps)
            let toClose = runningNames.subtracting(profileAppSet).subtracting(["Finder", "DevPulse"]).sorted()
            let toLaunch = profileAppSet.subtracting(runningNames).sorted()
            appState.pendingSwitchProfile = profile
            appState.appsToClose = toClose
            appState.appsToLaunch = toLaunch

        case .executeSwitchProfile(let profile):
            appState.pendingSwitchProfile = nil
            appState.isSwitchingProfile = true
            appState.profileSwitchResult = nil
            popover.performClose(nil)
            appState.sessionProfileManager.switchTo(profile) { [weak self] msg in
                self?.appState.profileSwitchResult = msg
                self?.appState.isSwitchingProfile = false
                self?.appState.detectedProfile = self?.appState.sessionProfileManager.detectCurrentProfile()
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    self?.appState.profileSwitchResult = nil
                }
            }

        case .cancelSwitchProfile:
            appState.pendingSwitchProfile = nil
            appState.appsToClose = []
            appState.appsToLaunch = []

        case .showSettings:
            popover.performClose(nil)
            showSettingsPanel()

        case .addProfile(let profile):
            appState.sessionProfileManager.addProfile(profile)
            appState.objectWillChange.send()

        case .deleteProfile(let id):
            appState.sessionProfileManager.deleteProfile(id: id)
            appState.objectWillChange.send()

        case .updateProfile(let profile):
            appState.sessionProfileManager.updateProfile(profile)
            appState.objectWillChange.send()

        case .toggleLearnMode:
            appState.sessionProfileManager.learnModeEnabled.toggle()
            appState.objectWillChange.send()

        case .acceptLearnedPattern(let pattern):
            let profile = SessionProfile(
                id: pattern.id,
                name: pattern.suggestedName,
                apps: pattern.apps,
                estimatedRAMGB: Double(pattern.apps.count) * 2,
                icon: pattern.suggestedIcon,
                isBuiltIn: false
            )
            appState.sessionProfileManager.addProfile(profile)
            appState.learnedPatterns.removeAll { $0.id == pattern.id }
            appState.objectWillChange.send()

        case .dismissLearnedPattern(let pattern):
            appState.learnedPatterns.removeAll { $0.id == pattern.id }

        case .ollamaUnloadModel(let name):
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                _ = self?.ollamaMonitor.unloadModel(name)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.refreshData() }
            }

        case .ollamaUnloadAll:
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                _ = self?.ollamaMonitor.unloadAllModels()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.refreshData() }
            }

        case .ollamaLoadModel(let name):
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                _ = self?.ollamaMonitor.loadModel(name)
                DispatchQueue.main.async { self?.refreshData() }
            }

        case .ollamaDeleteModel(let name):
            let alert = NSAlert()
            alert.messageText = "Delete \(name)?"
            alert.informativeText = "This removes the model from disk. You can re-pull it later with `ollama pull \(name)`."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    _ = self?.ollamaMonitor.deleteModel(name)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.refreshData() }
                }
            }

        case .ollamaPullModel(let slug):
            // One pull at a time. If a pull is already running, ignore.
            if activePull != nil { break }
            let manager = OllamaPullManager(
                modelName: slug,
                baseURL: "http://127.0.0.1:11434"
            ) { [weak self] state in
                guard let self = self else { return }
                self.appState.ollamaPull = state
                if state.isComplete {
                    self.activePull = nil
                    // Refresh installed-list to surface the new model.
                    self.refreshData()
                    // Auto-clear the success row after a short delay.
                    if state.error == nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            if self.appState.ollamaPull?.modelName == state.modelName,
                               self.appState.ollamaPull?.isComplete == true {
                                self.appState.ollamaPull = nil
                            }
                        }
                    }
                }
            }
            activePull = manager
            manager.start()

        case .ollamaCancelPull:
            activePull?.cancel()
            activePull = nil

        case .ollamaDeleteStale:
            let stale = appState.ollamaStatus?.staleInstalledModels ?? []
            guard !stale.isEmpty else { break }
            let alert = NSAlert()
            let totalMB = stale.reduce(0) { $0 + $1.sizeMB }
            let totalStr = totalMB >= 1024 ? String(format: "%.1f GB", Double(totalMB) / 1024) : "\(totalMB) MB"
            alert.messageText = "Delete \(stale.count) stale model\(stale.count == 1 ? "" : "s")?"
            alert.informativeText = "Reclaims \(totalStr) by removing models unused for 30+ days:\n\n" +
                stale.map { "• \($0.name) (\($0.sizeFormatted))" }.joined(separator: "\n")
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Delete All")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    for m in stale {
                        _ = self?.ollamaMonitor.deleteModel(m.name)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.refreshData() }
                }
            }

        case .killPort(let pid):
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                killPortProcess(pid)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.refreshData() }
            }

        case .cleanArtifacts(let artifacts):
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                _ = cleanDevArtifacts(artifacts)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.refreshData() }
            }

        case .debugWeeklySummary:
            ramAdvisor.debugTriggerWeeklySummary()

        case .quitApp:
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Settings Panel

    private var settingsPanel: NSPanel?

    private func showSettingsPanel() {
        if let existing = settingsPanel {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "DevPulse Settings"
        panel.isFloatingPanel = true
        panel.center()

        let settingsView = SettingsView(
            state: appState,
            prefs: Preferences.shared,
            onAction: { [weak self] action in
                self?.handleAction(action)
            }
        )
        panel.contentView = NSHostingView(rootView: settingsView)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsPanel = panel
    }

    // MARK: - Update Check

    private func checkForUpdates() {
        guard let url = URL(string: "https://api.github.com/repos/Gdewilde/devpulse/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String else { return }

            let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            DispatchQueue.main.async {
                self?.appState.latestVersion = version
                self?.appState.latestReleaseURL = htmlURL
            }
        }.resume()
    }

    // MARK: - Babysit Dashboard

    private var babysitPanel: NSPanel?

    private func showBabysitDashboard() {
        if let existing = babysitPanel {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Babysit Dashboard"
        panel.isFloatingPanel = false
        panel.center()
        panel.contentView = NSHostingView(rootView: BabysitDashboardView())
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        babysitPanel = panel
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

        if let gpu = appState.gpuMemory {
            subheading("GPU / Unified Memory (for Local AI)")
            mono("GPU allocated:       \(gpu.allocatedFormatted)")
            mono("Recommended max:     \(String(format: "%.1f GB", gpu.recommendedMaxGB))")
            mono("Available for AI:    \(gpu.availableForAIFormatted)")
        }

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
            subheading("Can I Run AI Models?")
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
