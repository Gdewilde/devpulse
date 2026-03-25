import SwiftUI
import AppKit

// MARK: - App Entry Point

@main
struct MemoryHealthEntry {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

// MARK: - Usage Bar

class UsageBarView: NSView {
    var usedPercent: Double = 0
    var status: HealthStatus = .healthy

    override var intrinsicContentSize: NSSize {
        NSSize(width: 240, height: 6)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let barRect = NSRect(x: 20, y: 0, width: bounds.width - 40, height: 4)

        let trackPath = NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2)
        NSColor.separatorColor.setFill()
        trackPath.fill()

        let fillWidth = barRect.width * CGFloat(min(usedPercent, 100) / 100)
        let fillRect = NSRect(x: barRect.minX, y: barRect.minY, width: fillWidth, height: barRect.height)
        let fillColor: NSColor
        switch status {
        case .healthy:  fillColor = .systemGreen
        case .warning:  fillColor = .systemOrange
        case .critical: fillColor = .systemRed
        }
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2)
        fillColor.setFill()
        fillPath.fill()
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private var stats = MemoryStats.current()
    private var cachedProcesses: [ProcessInfo_Memory] = []
    private var previousSwapGB: Double? = nil
    private var swapTrend: SwapTrend = .stable

    enum SwapTrend: String {
        case rising = "↑"
        case falling = "↓"
        case stable = ""
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateDisplay()
        refreshProcesses()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.stats = MemoryStats.current()
            self?.updateDisplay()
            self?.refreshProcesses()
        }
    }

    private func refreshProcesses() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let procs = getTopProcesses(limit: 8)
            DispatchQueue.main.async {
                self?.cachedProcesses = procs
                self?.buildMenu()
            }
        }
    }

    private func updateSwapTrend() {
        let currentSwap = stats.swapUsedGB
        if let prev = previousSwapGB {
            let delta = currentSwap - prev
            if delta > 0.5 { swapTrend = .rising }
            else if delta < -0.5 { swapTrend = .falling }
            else { swapTrend = .stable }
        }
        previousSwapGB = currentSwap
    }

    private func updateDisplay() {
        guard let button = statusItem.button else { return }
        updateSwapTrend()

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

        let swapSuffix = swapTrend == .stable ? "" : " \(swapTrend.rawValue)"
        button.title = " \(Int(stats.usedPercent))%\(swapSuffix)"
        button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        buildMenu()
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()
        menu.minimumWidth = 260

        // ── Header: "31.6 / 64 GB   49%" ──
        let headerItem = NSMenuItem()
        headerItem.isEnabled = false
        let usedStr = String(format: "%.0f", stats.usedGB)
        let totalStr = String(format: "%.0f", stats.totalGB)
        let pctStr = "\(Int(stats.usedPercent))%"

        let header = NSMutableAttributedString()
        header.append(attr(usedStr, font: .monospacedSystemFont(ofSize: 22, weight: .semibold), color: .labelColor))
        header.append(attr(" / \(totalStr) GB", font: .systemFont(ofSize: 13), color: .tertiaryLabelColor))
        header.append(attr("   \(pctStr)", font: .monospacedSystemFont(ofSize: 13, weight: .medium), color: statusColor()))
        headerItem.attributedTitle = header
        menu.addItem(headerItem)

        // ── Usage bar ──
        let barItem = NSMenuItem()
        let barView = UsageBarView(frame: NSRect(x: 0, y: 0, width: 260, height: 8))
        barView.usedPercent = stats.usedPercent
        barView.status = stats.status
        barItem.view = barView
        menu.addItem(barItem)
        menu.addItem(NSMenuItem.separator())

        // ── Key stats (only what matters) ──
        addRow(menu, "Free",       fmt(stats.freeGB))
        addRow(menu, "Compressed", fmt(stats.compressedGB))

        let swapVal = swapTrend == .stable ? fmt(stats.swapUsedGB) : "\(fmt(stats.swapUsedGB)) \(swapTrend.rawValue)"
        if stats.swapUsedGB >= 10 {
            addRow(menu, "Swap", swapVal, valueColor: stats.swapUsedGB >= 30 ? .systemRed : .systemOrange)
        } else {
            addRow(menu, "Swap", swapVal)
        }

        menu.addItem(NSMenuItem.separator())

        // ── Processes ──
        for proc in cachedProcesses {
            let item = NSMenuItem()
            let row = NSMutableAttributedString()

            // Dot
            let dotColor: NSColor = proc.isHigh ? .systemRed : proc.isElevated ? .systemOrange : .tertiaryLabelColor
            row.append(attr("●  ", font: .systemFont(ofSize: 6), color: dotColor, baseline: 2))

            // Name
            row.append(attr(proc.displayName, font: .systemFont(ofSize: 12), color: .labelColor))

            // Value
            let memColor: NSColor = proc.isHigh ? .systemRed : proc.isElevated ? .systemOrange : .secondaryLabelColor
            row.append(attr("  \(proc.memoryFormatted)", font: .monospacedSystemFont(ofSize: 11, weight: .medium), color: memColor))

            item.attributedTitle = row

            // Submenu: Quit / Force Quit
            let sub = NSMenu()
            if proc.canGracefulQuit {
                let q = NSMenuItem(title: "Quit \(proc.name)", action: #selector(gracefulQuitProcess(_:)), keyEquivalent: "")
                q.target = self
                q.representedObject = proc
                sub.addItem(q)
            }
            let fq = NSMenuItem(title: "Force Quit \(proc.name)", action: #selector(forceQuitProcess(_:)), keyEquivalent: "")
            fq.target = self
            fq.representedObject = proc
            sub.addItem(fq)
            item.submenu = sub

            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // ── Actions ──
        let fullCheck = NSMenuItem(title: "Run Full Check", action: #selector(runFullCheck), keyEquivalent: "r")
        fullCheck.target = self
        menu.addItem(fullCheck)

        let autoFix = NSMenuItem(title: "Run Auto-Fix", action: #selector(runAutoFix), keyEquivalent: "f")
        autoFix.target = self
        menu.addItem(autoFix)

        menu.addItem(NSMenuItem.separator())

        // ── Footer ──
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildTime = Bundle.main.infoDictionary?["BuildTimestamp"] as? String ?? "?"
        let vi = NSMenuItem()
        vi.isEnabled = false
        vi.attributedTitle = attr("v\(version)  \(buildTime)", font: .monospacedSystemFont(ofSize: 9, weight: .regular), color: .quaternaryLabelColor)
        menu.addItem(vi)

        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.delegate = self
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        stats = MemoryStats.current()
        buildMenu()
    }

    // MARK: - Helpers

    private func addRow(_ menu: NSMenu, _ label: String, _ value: String, valueColor: NSColor = .labelColor) {
        let item = NSMenuItem()
        item.isEnabled = false
        let row = NSMutableAttributedString()
        row.append(attr(label.padding(toLength: 13, withPad: " ", startingAt: 0),
                        font: .systemFont(ofSize: 12), color: .secondaryLabelColor))
        row.append(attr(value, font: .monospacedSystemFont(ofSize: 12, weight: .medium), color: valueColor))
        item.attributedTitle = row
        menu.addItem(item)
    }

    private func attr(_ string: String, font: NSFont, color: NSColor, baseline: Double = 0) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if baseline != 0 { attrs[.baselineOffset] = baseline }
        return NSAttributedString(string: string, attributes: attrs)
    }

    private func statusColor() -> NSColor {
        switch stats.status {
        case .healthy:  return .systemGreen
        case .warning:  return .systemOrange
        case .critical: return .systemRed
        }
    }

    private func fmt(_ gb: Double) -> String { String(format: "%.1f GB", gb) }

    // MARK: - Actions

    @objc private func gracefulQuitProcess(_ sender: NSMenuItem) {
        guard let proc = sender.representedObject as? ProcessInfo_Memory,
              let bundleName = proc.appBundleName else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let script = "tell application \"\(bundleName)\" to quit"
            let osa = Process()
            osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            osa.arguments = ["-e", script]
            try? osa.run()
            osa.waitUntilExit()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.refreshProcesses() }
        }
    }

    @objc private func forceQuitProcess(_ sender: NSMenuItem) {
        guard let proc = sender.representedObject as? ProcessInfo_Memory else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for pid in proc.pids { kill(pid, SIGKILL) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.refreshProcesses() }
        }
    }

    @objc private func runFullCheck() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Terminal", "/Users/gj/Apps/claude/memory-health/mem-check.sh"]
        try? p.run()
    }

    @objc private func runAutoFix() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Terminal", "/Users/gj/Apps/claude/memory-health/mem-check.sh", "--args", "--fix"]
        try? p.run()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
