import Foundation
import UserNotifications

// MARK: - Auto-Optimizer Agent
// Runs in the background, continuously monitors, and takes safe optimization actions.

class AutoOptimizer {
    private var timer: Timer?
    private let interval: TimeInterval = 300 // 5 minutes
    private let logPath: URL
    private var lastChromeNotification: Date = .distantPast
    private var lastIdleNotification: Date = .distantPast
    private var killedZombiePids: Set<Int32> = [] // avoid double-killing
    weak var appState: AppState?

    // Thresholds
    let zombieMinAgeSec: TimeInterval = 1800  // 30 min before auto-kill
    let chromeWarnGB: Double = 10.0           // Notify when Chrome exceeds
    let chromeNotifyCooldown: TimeInterval = 3600  // 1 hour between Chrome nags
    let idleNotifyCooldown: TimeInterval = 1800    // 30 min between idle nags

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("DevPulse")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logPath = dir.appendingPathComponent("optimizer-log.txt")
    }

    func start() {
        log("Auto-optimizer started")
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.runCycle()
        }
        // Run first cycle after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.runCycle()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        log("Auto-optimizer stopped")
    }

    // MARK: - Optimization Cycle

    private func runCycle() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            self.autoKillZombies()
            self.checkIdleServers()
            self.checkChromeMemory()
        }
    }

    // MARK: - Auto-Kill Zombies

    private func autoKillZombies() {
        let zombies = getZombieProcesses()
        guard !zombies.isEmpty else { return }

        var killed = 0
        var freedMB = 0

        for group in zombies {
            for pid in group.pids {
                guard !killedZombiePids.contains(pid) else { continue }
                // Send SIGTERM first (graceful)
                kill(pid, SIGTERM)
                killedZombiePids.insert(pid)
                killed += 1
            }
            freedMB += group.totalMB
        }

        // Force kill after 3 seconds
        if killed > 0 {
            Thread.sleep(forTimeInterval: 3)
            for group in zombies {
                for pid in group.pids { kill(pid, SIGKILL) }
            }

            let freedStr = freedMB >= 1024
                ? String(format: "%.1f GB", Double(freedMB) / 1024)
                : "\(freedMB) MB"
            let projects = zombies.map(\.project).joined(separator: ", ")

            log("Killed \(killed) zombie processes (\(freedStr)) from: \(projects)")
            notify(
                title: "Cleaned \(killed) zombies",
                body: "Freed \(freedStr) from orphaned processes (\(projects))"
            )

            DispatchQueue.main.async { [weak self] in
                self?.appState?.optimizerStats.zombiesKilled += killed
                self?.appState?.optimizerStats.memoryFreedMB += freedMB
                self?.appState?.optimizerStats.lastAction = "Killed \(killed) zombies (\(freedStr))"
                self?.appState?.optimizerStats.lastActionTime = Date()
            }
        }

        // Prune old PIDs from tracking set (they may have been recycled)
        if killedZombiePids.count > 500 {
            killedZombiePids = Set(killedZombiePids.suffix(100))
        }
    }

    // MARK: - Check Idle Dev Servers

    private func checkIdleServers() {
        let inactive = getInactiveDevServers()
        guard !inactive.isEmpty else { return }

        let now = Date()
        guard now.timeIntervalSince(lastIdleNotification) >= idleNotifyCooldown else { return }

        let totalMB = inactive.reduce(0) { $0 + $1.totalMB }
        guard totalMB >= 50 else { return }

        let totalStr = totalMB >= 1024
            ? String(format: "%.1f GB", Double(totalMB) / 1024)
            : "\(totalMB) MB"
        let projects = inactive.map(\.project).joined(separator: ", ")
        let count = inactive.reduce(0) { $0 + $1.processes.count }

        log("Idle dev servers detected: \(count) processes using \(totalStr) for: \(projects)")
        notify(
            title: "Idle dev servers using \(totalStr)",
            body: "\(projects) — \(count) processes running with no IDE open. Kill them from DevPulse."
        )
        lastIdleNotification = now

        DispatchQueue.main.async { [weak self] in
            self?.appState?.optimizerStats.idleServerWarnings += 1
            self?.appState?.optimizerStats.lastAction = "Flagged idle servers: \(projects)"
            self?.appState?.optimizerStats.lastActionTime = Date()
        }
    }

    // MARK: - Check Chrome Memory

    private func checkChromeMemory() {
        // Quick check: look for Chrome in top processes
        let procs = getTopProcesses(limit: 3)
        guard let chrome = procs.first(where: { $0.name == "Chrome" }) else { return }

        let chromeGB = Double(chrome.memoryMB) / 1024
        guard chromeGB >= chromeWarnGB else { return }

        let now = Date()
        guard now.timeIntervalSince(lastChromeNotification) >= chromeNotifyCooldown else { return }

        let chromeStr = String(format: "%.1f GB", chromeGB)
        let stats = getChromeStats()
        let tabInfo = stats.map { " (\($0.tabCount) tabs)" } ?? ""

        log("Chrome using \(chromeStr)\(tabInfo) — suggesting restart")
        notify(
            title: "Chrome is using \(chromeStr)\(tabInfo)",
            body: "Restart Chrome to reclaim leaked memory. Enable Memory Saver in Chrome settings to prevent this."
        )
        lastChromeNotification = now

        DispatchQueue.main.async { [weak self] in
            self?.appState?.optimizerStats.chromeWarnings += 1
            self?.appState?.optimizerStats.lastAction = "Chrome warning: \(chromeStr)\(tabInfo)"
            self?.appState?.optimizerStats.lastActionTime = Date()
        }
    }

    // MARK: - Logging & Notifications

    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath.path) {
                if let handle = try? FileHandle(forWritingTo: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logPath, options: .atomic)
            }
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "devpulse-auto-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
