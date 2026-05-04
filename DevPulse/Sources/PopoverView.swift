import SwiftUI

// MARK: - Main Popover

struct PopoverView: View {
    @ObservedObject var state: AppState
    var onAction: (AppAction) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HeaderSection(state: state)

                if state.ollamaStatus?.isRunning == true || state.aiMemoryBudget != nil {
                    Divider().padding(.horizontal, 16)
                    AIMemorySection(state: state, onAction: onAction)
                }

                if !state.modelResults.isEmpty {
                    Divider().padding(.horizontal, 16)
                    CanIRunSection(state: state, onAction: onAction)
                }

                Divider().padding(.horizontal, 16)
                ProcessSection(state: state, onAction: onAction)

                if hasOverhead {
                    Divider().padding(.horizontal, 16)
                    OverheadSection(state: state, onAction: onAction)
                }

                if !state.zombies.isEmpty {
                    Divider().padding(.horizontal, 16)
                    ZombieSection(state: state, onAction: onAction)
                }

                if !state.appRecommendations.isEmpty {
                    Divider().padding(.horizontal, 16)
                    AlternativesSection(state: state, onAction: onAction)
                }

                if state.verdict != nil {
                    Divider().padding(.horizontal, 16)
                    VerdictCard(state: state, onAction: onAction)
                }

                if let ports = state.portScan, ports.devPortCount > 0 {
                    Divider().padding(.horizontal, 16)
                    PortSection(state: state, onAction: onAction)
                }

                if let artifacts = state.devArtifactScan, artifacts.totalMB >= 100 {
                    Divider().padding(.horizontal, 16)
                    DevArtifactSection(state: state, onAction: onAction)
                }

                Divider().padding(.horizontal, 16)
                ActionSection(state: state, onAction: onAction)

                if state.detectedProfile != nil || !state.sessionProfileManager.profiles.isEmpty {
                    Divider().padding(.horizontal, 16)
                    SessionProfileSection(state: state, onAction: onAction)
                }

                // Quit button
                Button { onAction(.quitApp) } label: {
                    HStack {
                        Text("Quit DevPulse")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Q")
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)

                FooterSection(state: state, onAction: onAction)
            }
        }
        .frame(width: 340)
        .frame(maxHeight: 580)
    }

    private var hasOverhead: Bool {
        state.dockerStats != nil || state.electronStats != nil || !state.inactiveServers.isEmpty
    }
}

// MARK: - Header

struct HeaderSection: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Big memory readout
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(state.stats.usedGB))")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("/ \(Int(state.stats.totalGB)) GB")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(Int(state.stats.usedPercent))%")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(pctColor)
            }

            // Usage bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barGradient)
                        .frame(width: geo.size.width * CGFloat(min(state.stats.usedPercent, 100) / 100), height: 6)
                }
            }
            .frame(height: 6)

            // Stats chips
            HStack(spacing: 12) {
                StatChip(label: "Free", value: fmt(state.stats.freeGB))
                StatChip(label: "Compressed", value: fmt(state.stats.compressedGB))
                StatChip(label: "Swap", value: swapText, accent: swapColor)
                if let gpu = state.gpuMemory {
                    StatChip(label: "GPU (VRAM)", value: gpu.allocatedFormatted)
                }
            }
            HStack(spacing: 12) {
                if let ssd = state.ssdHealth, ssd.available {
                    StatChip(label: "SSD Written", value: ssd.dataWrittenFormatted)
                }
                if let gpu = state.gpuMemory {
                    StatChip(label: "GPU Avail for AI", value: gpu.availableForAIFormatted)
                }
                if let b = state.battery {
                    StatChip(label: batteryLabel(b), value: batteryValue(b), accent: batteryColor(b))
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var pctColor: Color {
        state.stats.status == .critical ? .red : state.stats.status == .warning ? .orange : .secondary
    }

    private var barGradient: LinearGradient {
        let pct = state.stats.usedPercent
        let color: Color = pct >= 90 ? .red : pct >= 75 ? .orange : .green
        return LinearGradient(colors: [color.opacity(0.8), color], startPoint: .leading, endPoint: .trailing)
    }

    private var swapText: String {
        let val = fmt(state.stats.swapUsedGB)
        return state.swapTrend == .stable ? val : "\(val) \(state.swapTrend.rawValue)"
    }

    private var swapColor: Color? {
        state.stats.swapUsedGB >= 30 ? .red : state.stats.swapUsedGB >= 10 ? .orange : nil
    }

    private func batteryLabel(_ b: BatteryStats) -> String {
        if b.lowPowerMode { return "Battery (LPM)" }
        if b.onAC { return b.isCharging ? "Battery ⚡︎" : "Battery (AC)" }
        return "Battery"
    }

    private func batteryValue(_ b: BatteryStats) -> String {
        if let m = b.timeToEmptyMinutes, m > 0, !b.onAC {
            return "\(b.percent)% · \(m / 60)h \(m % 60)m"
        }
        return "\(b.percent)%"
    }

    private func batteryColor(_ b: BatteryStats) -> Color? {
        if b.onAC { return nil }
        if b.percent <= 10 { return .red }
        if b.percent <= 20 { return .orange }
        return nil
    }
}

struct StatChip: View {
    let label: String
    let value: String
    var accent: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(accent ?? .secondary)
        }
    }
}

// MARK: - Processes

struct ProcessSection: View {
    @ObservedObject var state: AppState
    var onAction: (AppAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Processes")
            ForEach(state.processes.prefix(8)) { proc in
                ProcessRow(
                    proc: proc,
                    chromeStats: proc.name == "Chrome" ? state.chromeStats : nil,
                    onAction: onAction
                )
            }
        }
        .padding(.bottom, 4)
    }
}

struct ProcessRow: View {
    let proc: ProcessInfo_Memory
    let chromeStats: ChromeStats?
    var onAction: (AppAction) -> Void
    @State private var expanded = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(proc.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !expanded, let summary = proc.breakdownSummary {
                        Text(summary)
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(proc.memoryFormatted)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(memColor)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.quaternary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .onHover { isHovered = $0 }

            // Expanded detail
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    // Chrome-specific detail
                    if let chrome = chromeStats {
                        ChromeDetail(chrome: chrome, onAction: onAction)
                    }

                    // Process type breakdown
                    if proc.breakdown.count > 1 {
                        ForEach(proc.breakdown.prefix(6), id: \.name) { entry in
                            HStack(spacing: 0) {
                                let countStr = entry.count > 1 ? "\(entry.count)x " : ""
                                Text("\(countStr)\(entry.name)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(entry.mb >= 1024
                                    ? String(format: "%.1f GB", Double(entry.mb) / 1024)
                                    : "\(entry.mb) MB")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 2)
                        }
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        if proc.canGracefulQuit {
                            Button("Quit") { onAction(.quit(proc)) }
                                .font(.system(size: 11, weight: .medium))
                        }
                        Button("Force Quit") { onAction(.forceQuit(proc)) }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 5)
                }
                .background(Color.primary.opacity(0.02))
            }
        }
    }

    private var memColor: Color {
        proc.memoryMB >= 4000 ? .red : proc.memoryMB >= 2000 ? .orange : .secondary
    }
}

// MARK: - Chrome Detail

struct ChromeDetail: View {
    let chrome: ChromeStats
    var onAction: (AppAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab/window summary
            if chrome.tabCount > 0 {
                Text("\(chrome.tabCount) tabs in \(chrome.windowCount) windows")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 2)
            }

            // Memory breakdown by type
            if chrome.rendererMemoryMB > 0 {
                ChromeBreakdownRow("Tab renderers (\(chrome.rendererCount))", chrome.rendererMemoryMB)
            }
            if chrome.extensionMemoryMB > 0 {
                ChromeBreakdownRow("Extensions (\(chrome.extensionCount))", chrome.extensionMemoryMB)
            }
            if chrome.gpuMemoryMB > 0 {
                ChromeBreakdownRow("GPU process", chrome.gpuMemoryMB)
            }
            if chrome.utilityMemoryMB > 0 {
                ChromeBreakdownRow("Utilities", chrome.utilityMemoryMB)
            }

            if chrome.avgTabMB > 0 {
                Text("~\(chrome.avgTabMB) MB per tab avg")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 28)
                    .padding(.top, 4)
            }

            // Chrome-specific actions
            HStack(spacing: 12) {
                Button("Task Manager") { onAction(.chromeTaskManager) }
                Button("Memory Saver") { onAction(.chromeMemorySaver) }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.blue)
            .padding(.horizontal, 28)
            .padding(.vertical, 5)

            Divider().padding(.horizontal, 28).padding(.vertical, 2)
        }
    }
}

struct ChromeBreakdownRow: View {
    let label: String
    let mb: Int

    init(_ label: String, _ mb: Int) {
        self.label = label
        self.mb = mb
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(fmtMB(mb))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 2)
    }
}

// MARK: - Overhead

struct OverheadSection: View {
    @ObservedObject var state: AppState
    var onAction: (AppAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Overhead")

            if let docker = state.dockerStats {
                OverheadRow(
                    icon: "shippingbox",
                    text: docker.isIdle
                        ? "Docker idle, \(docker.vmFormatted) reserved"
                        : "\(docker.containerCount) containers using \(docker.containerFormatted)",
                    actionLabel: docker.wasteMB > 500 || docker.isIdle ? "Restart VM" : nil,
                    action: { onAction(.restartDockerVM) }
                )
                // OrbStack suggestion when Docker waste is chronic
                if isDockerWasteChronic(stats: docker) && !isOrbStackInstalled() {
                    OverheadRow(
                        icon: "lightbulb",
                        text: "Try OrbStack — lighter Docker alternative",
                        actionLabel: "Get it",
                        action: { onAction(.openURL("https://orbstack.dev")) }
                    )
                }
            }

            if let electron = state.electronStats {
                let wasteStr = electron.duplicateWasteMB >= 1024
                    ? String(format: "%.1f GB", Double(electron.duplicateWasteMB) / 1024)
                    : "\(electron.duplicateWasteMB) MB"
                OverheadRow(icon: "square.on.square", text: "\(electron.appCount) Electron apps, ~\(wasteStr) overlap")
            }

            ForEach(state.inactiveServers, id: \.project) { server in
                OverheadRow(
                    icon: "moon.zzz",
                    text: "\(server.project) idle — \(fmtMB(server.totalMB))",
                    actionLabel: "Kill",
                    action: { onAction(.killPids(server.pids)) }
                )
            }
        }
        .padding(.bottom, 4)
    }
}

struct OverheadRow: View {
    let icon: String
    let text: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let label = actionLabel, isHovered {
                Button(label) { action?() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - Zombies

struct ZombieSection: View {
    @ObservedObject var state: AppState
    var onAction: (AppAction) -> Void

    private var totalMB: Int { state.zombies.reduce(0) { $0 + $1.totalMB } }
    private var totalCount: Int { state.zombies.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Zombies")

            Button {
                let allPids = state.zombies.flatMap(\.pids)
                onAction(.killPids(allPids))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 11))
                    Text("Kill \(totalCount) zombies")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(fmtMB(totalMB))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            ForEach(Array(state.zombies.enumerated()), id: \.offset) { _, zombie in
                HStack(spacing: 4) {
                    Text(zombie.project)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(zombie.kind.rawValue)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.quaternary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary.opacity(0.3), in: Capsule())
                    Text("(\(zombie.count))")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                    Spacer()
                    Text(fmtMB(zombie.totalMB))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.quaternary)
                        .padding(.trailing, 8)
                    Button {
                        onAction(.killPids(zombie.pids))
                    } label: {
                        Text("Kill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
        .padding(.bottom, 4)
    }
}

// MARK: - "Should I Buy a New Mac?" Verdict Card

struct VerdictCard: View {
    @ObservedObject var state: AppState
    var onAction: (AppAction) -> Void
    @State private var isHovered = false

    var body: some View {
        if let verdict = state.verdict {
            Button {
                onAction(.openURL("https://devpulse.sh/do-i-need-a-new-mac"))
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    // The big question
                    HStack(spacing: 8) {
                        Text(emoji(verdict))
                            .font(.system(size: 24))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Do I need a new Mac?")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .tracking(0.5)
                            Text(funHeadline(verdict))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(headlineColor(verdict))
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .opacity(isHovered ? 1 : 0)
                    }

                    // The roast / explanation
                    Text(funDetail(verdict, state: state))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Waste breakdown pills
                    if verdict.waste.totalMB > 100 {
                        HStack(spacing: 6) {
                            if verdict.waste.zombieMB > 50 { WastePill("Zombies", verdict.waste.zombieMB) }
                            if verdict.waste.dockerMB > 50 { WastePill("Docker", verdict.waste.dockerMB) }
                            if verdict.waste.electronMB > 50 { WastePill("Electron", verdict.waste.electronMB) }
                            if verdict.waste.inactiveServerMB > 50 { WastePill("Idle servers", verdict.waste.inactiveServerMB) }
                        }
                    }

                    // Stats line
                    HStack(spacing: 8) {
                        Text("\(Int(verdict.peakUsedGB))G peak")
                        Text("\(Int(verdict.wasteGB))G reclaimable")
                        Text("\(verdict.daysTracked)d tracked")
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .background(cardBackground(verdict))
            .onHover { isHovered = $0 }
        }
    }

    private func emoji(_ v: RAMVerdict) -> String {
        switch v.rating {
        case .plenty:    return "😎"
        case .fine:      return "👍"
        case .tight:     return "😬"
        case .needsMore: return "💸"
        }
    }

    private func funHeadline(_ v: RAMVerdict) -> String {
        switch v.rating {
        case .plenty:    return "Absolutely not."
        case .fine:      return "Nope, you're good."
        case .tight:     return "Not yet — clean up first."
        case .needsMore: return "Yeah, probably."
        }
    }

    private func headlineColor(_ v: RAMVerdict) -> Color {
        switch v.rating {
        case .plenty, .fine: return .green
        case .tight: return .orange
        case .needsMore: return .red
        }
    }

    private func funDetail(_ v: RAMVerdict, state: AppState) -> String {
        let totalStr = "\(Int(v.totalRAMGB)) GB"
        let peakStr = "\(Int(v.peakUsedGB)) GB"
        let wasteStr = "\(Int(v.wasteGB)) GB"
        let optimizedStr = "\(Int(v.optimizedPeakGB)) GB"

        // Find the biggest offender for color
        let chromeGB = state.processes.first(where: { $0.name == "Chrome" })
            .map { String(format: "%.1f GB", Double($0.memoryMB) / 1024) }

        switch v.rating {
        case .plenty:
            if let cGB = chromeGB {
                return "You peaked at \(peakStr) on a \(totalStr) Mac. Even with Chrome hogging \(cGB), you have headroom for days."
            }
            return "Peaked at \(peakStr) on \(totalStr). You could run two more IDEs and still be fine."

        case .fine:
            if v.waste.totalMB > 500 {
                return "Peak \(peakStr), but \(wasteStr) is waste you can reclaim. After cleanup you'd use \(optimizedStr). Save your money."
            }
            return "Peak \(peakStr) on \(totalStr). Comfortable. Spend that money on coffee instead."

        case .tight:
            if let biggest = v.waste.biggestSource {
                let bigStr = fmtMB(biggest.mb)
                return "Peak \(peakStr) with \(wasteStr) reclaimable. Biggest culprit: \(bigStr) in \(biggest.name). Fix that before shopping for hardware."
            }
            return "Tight at \(peakStr) on \(totalStr), but \(wasteStr) is recoverable. Optimize before you upgrade."

        case .needsMore:
            if let cGB = chromeGB, (state.processes.first(where: { $0.name == "Chrome" })?.memoryMB ?? 0) > 10000 {
                return "Even optimized you'd peak at \(optimizedStr) on \(totalStr). But seriously, Chrome is using \(cGB). Maybe start there."
            }
            let nextMAC = v.totalRAMGB <= 16 ? "32 GB" : v.totalRAMGB <= 32 ? "64 GB" : "128 GB"
            return "Peak \(peakStr) with only \(wasteStr) waste. Even clean, \(optimizedStr) on \(totalStr) is tight. A \(nextMAC) Mac would give you breathing room."
        }
    }

    private func cardBackground(_ v: RAMVerdict) -> some ShapeStyle {
        switch v.rating {
        case .plenty, .fine: return Color.green.opacity(0.06)
        case .tight: return Color.orange.opacity(0.06)
        case .needsMore: return Color.red.opacity(0.06)
        }
    }
}

struct WastePill: View {
    let label: String
    let mb: Int

    init(_ label: String, _ mb: Int) {
        self.label = label
        self.mb = mb
    }

    var body: some View {
        Text("\(label) \(fmtMB(mb))")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }
}

// MARK: - Lighter Alternatives Section

struct AlternativesSection: View {
    @ObservedObject var state: AppState
    var onAction: (AppAction) -> Void
    @State private var expanded = false

    var body: some View {
        let recs = state.appRecommendations
        let totalSavings = recs.reduce(0) { $0 + $1.potentialSavingsMB }

        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    SectionLabel("Lighter Alternatives")
                    Spacer()
                    Text("save \(formatMBAlt(totalSavings))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.green)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("")
                        .frame(width: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            if !expanded {
                // Compact: top 3 offenders with best alternative
                ForEach(recs.prefix(3), id: \.offender.displayName) { rec in
                    CompactAlternativeRow(rec: rec, onAction: onAction)
                }
            } else {
                // Expanded: all recommendations with full alternative lists
                ForEach(recs, id: \.offender.displayName) { rec in
                    ExpandedAlternativeRow(rec: rec, onAction: onAction)
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func formatMBAlt(_ mb: Int) -> String {
        mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
    }
}

struct CompactAlternativeRow: View {
    let rec: AppRecommendation
    var onAction: (AppAction) -> Void

    var body: some View {
        if let best = rec.alternatives.max(by: { $0.savingsMB < $1.savingsMB }) {
            HStack(spacing: 8) {
                Image(systemName: rec.offender.icon)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(rec.offender.displayName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 7))
                    .foregroundStyle(.tertiary)
                Button {
                    if let url = best.url { onAction(.openURL(url)) }
                    else if let slug = rec.offender.websiteSlug {
                        onAction(.openURL("https://devpulse.sh/apps/\(slug)"))
                    }
                } label: {
                    Text(best.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("-\(formatMBRow(best.savingsMB))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 3)
        }
    }

    private func formatMBRow(_ mb: Int) -> String {
        mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
    }
}

struct ExpandedAlternativeRow: View {
    let rec: AppRecommendation
    var onAction: (AppAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Offender header
            HStack(spacing: 6) {
                Image(systemName: rec.offender.icon)
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .frame(width: 14)
                Text(rec.offender.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                Text("using \(formatMBExp(rec.currentMB))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
                if let slug = rec.offender.websiteSlug {
                    Button {
                        onAction(.openURL("https://devpulse.sh/apps/\(slug)"))
                    } label: {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            // Alternatives
            ForEach(rec.alternatives.sorted(by: { $0.savingsMB > $1.savingsMB }), id: \.id) { alt in
                HStack(spacing: 6) {
                    difficultyDot(alt.difficulty)
                    Button {
                        if let url = alt.url { onAction(.openURL(url)) }
                        else if let slug = alt.websiteSlug {
                            onAction(.openURL("https://devpulse.sh/apps/\(slug)"))
                        }
                    } label: {
                        Text(alt.name)
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                    Text(alt.tradeoff)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Spacer()
                    Text("-\(formatMBExp(alt.savingsMB))")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 1)
            }
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func difficultyDot(_ d: AppAlternative.Difficulty) -> some View {
        Circle()
            .fill(d == .easy ? Color.green : d == .medium ? Color.orange : Color.red)
            .frame(width: 5, height: 5)
    }

    private func formatMBExp(_ mb: Int) -> String {
        mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
    }
}

// MARK: - Port Section

struct PortSection: View {
    @ObservedObject var state: AppState
    var onAction: (AppAction) -> Void
    @State private var expanded = false

    var body: some View {
        if let scan = state.portScan {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        SectionLabel("Ports")
                        if scan.hasIssues {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Text("\(scan.devPortCount) listening")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                        Text("")
                            .frame(width: 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)

                // System conflicts (always shown)
                ForEach(scan.systemConflicts) { port in
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Text(":\(port.port)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Text(port.processName)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text("(system conflict)")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }

                // Port conflicts (always shown)
                ForEach(scan.conflicts, id: \.port) { conflict in
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                        Text(":\(conflict.port)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Text("\(conflict.holders.count) processes")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }

                if expanded {
                    let devPorts = scan.ports.filter(\.isDevPort)
                    ForEach(devPorts) { port in
                        PortRow(port: port, onAction: onAction)
                    }
                }
            }
            .padding(.bottom, 4)
        }
    }
}

struct PortRow: View {
    let port: ListeningPort
    var onAction: (AppAction) -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(":\(port.port)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 50, alignment: .trailing)
            Text(port.displayName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if isHovered {
                Button {
                    onAction(.killPort(port.pid))
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - Dev Artifact Section

struct DevArtifactSection: View {
    @ObservedObject var state: AppState
    var onAction: (AppAction) -> Void
    @State private var expanded = false

    var body: some View {
        if let scan = state.devArtifactScan {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        SectionLabel("Dev Disk Usage")
                        Spacer()
                        Text(scan.totalFormatted)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(scan.totalMB >= 10240 ? Color.orange : .secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                        Text("")
                            .frame(width: 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)

                // Compact: top categories
                if !expanded {
                    ForEach(scan.byCategory.prefix(3), id: \.category) { cat in
                        HStack(spacing: 8) {
                            Image(systemName: artifactIcon(cat.category))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                            Text(cat.category)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            if cat.count > 1 {
                                Text("(\(cat.count))")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text(formatMB(cat.totalMB))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 2)
                    }
                } else {
                    // Expanded: all artifacts with cleanup
                    ForEach(scan.artifacts.prefix(15)) { artifact in
                        ArtifactRow(artifact: artifact, onAction: onAction)
                    }

                    // Stale cleanup button
                    let staleItems = scan.artifacts.filter(\.isStale)
                    if !staleItems.isEmpty {
                        Button {
                            onAction(.cleanArtifacts(staleItems))
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 9))
                                Text("Clean stale artifacts (\(scan.staleFormatted))")
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func artifactIcon(_ category: String) -> String {
        switch category {
        case "node_modules": return "shippingbox"
        case "Homebrew Cache": return "mug"
        case "Cargo Registry": return "gearshape"
        case "Gradle Cache": return "building.2"
        case "pip Cache": return "circle.grid.3x3"
        case "CocoaPods Cache": return "leaf"
        case "Ollama Models": return "brain"
        case "HuggingFace Cache": return "face.smiling"
        case "npm Cache", "Yarn Cache", "pnpm Cache", "Bun Cache": return "shippingbox"
        default: return "folder"
        }
    }

    private func formatMB(_ mb: Int) -> String {
        mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
    }
}

struct ArtifactRow: View {
    let artifact: DevArtifact
    var onAction: (AppAction) -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(artifact.project ?? artifact.category)
                    .font(.system(size: 10))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(artifact.category)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    if artifact.isStale {
                        Text("\(artifact.daysSinceAccess)d old")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Text(artifact.sizeFormatted)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            if isHovered {
                Button {
                    onAction(.cleanArtifacts([artifact]))
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - AI Memory Section

struct AIMemorySection: View {
    @ObservedObject var state: AppState
    var onAction: (AppAction) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    SectionLabel("AI Memory")
                    if let ollama = state.ollamaStatus, ollama.isRunning {
                        Text("\(ollama.loadedModels.count) model\(ollama.loadedModels.count == 1 ? "" : "s")")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if let budget = state.aiMemoryBudget {
                        Text(budget.availableForAIFormatted + " free")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("")
                        .frame(width: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            // Active pull progress (if any)
            if let pull = state.ollamaPull {
                PullProgressRow(pull: pull, onAction: onAction)
            }

            // Ollama not running: show neutral runtime panel
            if state.ollamaStatus?.isRunning != true {
                LocalRuntimePanel(runtimes: state.localAIRuntimes, onAction: onAction)
            }

            // Ollama status + loaded models
            if let ollama = state.ollamaStatus, ollama.isRunning {
                if !ollama.loadedModels.isEmpty {
                    ForEach(ollama.loadedModels, id: \.name) { model in
                        OllamaModelRow(model: model, onAction: onAction)
                    }

                    // Unload all button if multiple models
                    if ollama.loadedModels.count > 1 {
                        Button {
                            onAction(.ollamaUnloadAll)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 9))
                                Text("Unload all (\(ollama.totalVRAMFormatted))")
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 44)
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.borderless)
                    }

                    // Idle model warning
                    if ollama.hasIdleModels {
                        HStack(spacing: 4) {
                            Image(systemName: "moon.zzz.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                            Text("\(ollama.idleVRAMFormatted) held by idle model\(ollama.idleModels.count == 1 ? "" : "s")")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 3)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 9))
                            .foregroundStyle(.green)
                        Text("Ollama running — no models loaded")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 3)
                }

                // Installed-on-disk summary (always shown when expanded)
                if expanded && !ollama.installedModels.isEmpty {
                    Text("INSTALLED ON DISK")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)

                    HStack(spacing: 4) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text("\(ollama.installedModels.count) model\(ollama.installedModels.count == 1 ? "" : "s") · \(ollama.installedDiskFormatted) on disk")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)

                    ForEach(ollama.unloadedInstalledModels, id: \.name) { model in
                        InstalledModelRow(model: model, onAction: onAction)
                    }

                    if ollama.staleDiskMB > 0 {
                        let staleMB = ollama.staleDiskMB
                        let staleStr = staleMB >= 1024
                            ? String(format: "%.1f GB", Double(staleMB) / 1024)
                            : "\(staleMB) MB"
                        Button {
                            onAction(.ollamaDeleteStale)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.badge.exclamationmark")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.orange)
                                Text("Reclaim \(staleStr) — \(ollama.staleInstalledModels.count) model\(ollama.staleInstalledModels.count == 1 ? "" : "s") unused 30+ days")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.orange)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            // Expanded: memory budget breakdown
            if expanded, let budget = state.aiMemoryBudget {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MEMORY BUDGET")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .padding(.top, 4)

                    AIBudgetBar(budget: budget)

                    BudgetRow(label: "Total RAM", valueMB: budget.totalRAMMB, color: .primary)
                    BudgetRow(label: "GPU Ceiling (75%)", valueMB: budget.gpuCeilingMB, color: .secondary)
                    BudgetRow(label: "Dev Stack (IDE/Docker/etc)", valueMB: budget.devStackMB, color: .blue)
                    if budget.ollamaModelsMB > 0 {
                        BudgetRow(label: "Ollama Models", valueMB: budget.ollamaModelsMB, color: .purple)
                    }
                    BudgetRow(label: "Available for AI", valueMB: budget.availableForAIMB, color: .green)
                    if budget.reclaimableFromIdleMB > 0 {
                        BudgetRow(label: "Reclaimable (idle)", valueMB: budget.reclaimableFromIdleMB, color: .orange)
                    }

                    // Context window estimates
                    if budget.availableForAIMB > 512 || budget.reclaimableFromIdleMB > 0 {
                        Text("MAX CONTEXT (ESTIMATE)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                            .padding(.top, 6)

                        contextRow("7B model", budget.maxContextTokens(modelParamB: 7))
                        contextRow("14B model", budget.maxContextTokens(modelParamB: 14))
                        contextRow("32B model", budget.maxContextTokens(modelParamB: 32))
                        contextRow("70B model", budget.maxContextTokens(modelParamB: 70))
                    }

                    // Fragmentation warning
                    if let warning = budget.fragmentationWarning {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                            Text(warning)
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                        }
                        .padding(.top, 4)
                    }

                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
        }
        .padding(.bottom, 4)
    }


    @ViewBuilder
    private func contextRow(_ name: String, _ tokens: Int) -> some View {
        if tokens > 0 {
            HStack {
                Text(name)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatTokens(tokens))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(tokens >= 8192 ? Color.primary : Color.orange)
            }
        }
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 { return String(format: "%.0fM tokens", Double(tokens) / 1_000_000) }
        if tokens >= 1_000 { return String(format: "%.0fK tokens", Double(tokens) / 1_000) }
        return "\(tokens) tokens"
    }
}

struct OllamaModelRow: View {
    let model: LoadedModel
    var onAction: (AppAction) -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain")
                .font(.system(size: 9))
                .foregroundStyle(.purple)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !model.quantization.isEmpty {
                        Text(model.quantization)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    if let idle = model.idleDuration {
                        Text(idle)
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Text(model.sizeFormatted)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            if isHovered {
                Button {
                    onAction(.ollamaUnloadModel(model.name))
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

struct LocalRuntimePanel: View {
    let runtimes: LocalAIRuntimes
    var onAction: (AppAction) -> Void

    /// All four options, presented equally. Order: alphabetical by name to
    /// avoid implying a preference.
    private var options: [(name: String, url: String, installed: Bool, startCmd: String?)] {
        [
            ("llama.cpp",  "https://github.com/ggerganov/llama.cpp", runtimes.llamaCppInstalled, nil),
            ("LM Studio",  "https://lmstudio.ai",                   runtimes.lmStudioInstalled, "open -a 'LM Studio'"),
            ("MLX",        "https://github.com/ml-explore/mlx",     runtimes.mlxInstalled,      nil),
            ("Ollama",     "https://ollama.com/download",           runtimes.ollamaInstalled,   "open -a Ollama"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Headline depends on detection state.
            HStack(spacing: 6) {
                Image(systemName: runtimes.anyInstalled ? "play.circle" : "shippingbox")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(runtimes.anyInstalled
                     ? "Local AI runtime detected — start it to begin"
                     : "Run AI models locally — pick a runtime")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            // Equal grid of options. Installed ones get a "start" button;
            // not-installed ones get a "get" link.
            VStack(spacing: 2) {
                ForEach(options, id: \.name) { opt in
                    HStack(spacing: 8) {
                        Image(systemName: opt.installed ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 9))
                            .foregroundStyle(opt.installed ? Color.green : Color.gray.opacity(0.5))
                            .frame(width: 12)
                        Text(opt.name)
                            .font(.system(size: 11))
                            .foregroundStyle(opt.installed ? .primary : .secondary)
                        Spacer()
                        if opt.installed, let cmd = opt.startCmd {
                            Button("Start") {
                                runShellCommand(cmd)
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.blue)
                        } else if !opt.installed {
                            Button("Get") {
                                onAction(.openURL(opt.url))
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.blue)
                        } else {
                            Text("installed")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func runShellCommand(_ cmd: String) {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", cmd]
        try? task.run()
    }
}

struct PullProgressRow: View {
    let pull: OllamaPullState
    var onAction: (AppAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: pull.error != nil ? "xmark.circle.fill" :
                                  pull.isComplete ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(pull.error != nil ? Color.red :
                                     pull.isComplete ? Color.green : Color.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pull.modelName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(pull.status)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        if !pull.bytesText.isEmpty {
                            Text(pull.bytesText)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer()
                Text(pull.percentText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(pull.error != nil ? .red : .primary)
                if !pull.isComplete {
                    Button {
                        onAction(.ollamaCancelPull)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Cancel pull")
                }
            }
            if pull.totalBytes > 0 && !pull.isComplete {
                ProgressView(value: pull.percent)
                    .progressViewStyle(.linear)
                    .tint(.blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

struct InstalledModelRow: View {
    let model: InstalledModel
    var onAction: (AppAction) -> Void
    @State private var isHovered = false
    @State private var loading = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !model.quantization.isEmpty {
                        Text(model.quantization)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    if model.daysSinceModified >= 30 {
                        Text("\(model.daysSinceModified)d old")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            Text(model.sizeFormatted)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)

            if isHovered {
                Button {
                    loading = true
                    onAction(.ollamaLoadModel(model.name))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { loading = false }
                } label: {
                    Image(systemName: loading ? "hourglass" : "play.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(loading ? Color.secondary : Color.green)
                }
                .buttonStyle(.borderless)
                .help("Load \(model.name) into VRAM")
                .disabled(loading)

                Button {
                    onAction(.ollamaDeleteModel(model.name))
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Delete \(model.name) from disk")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

struct AIBudgetBar: View {
    let budget: AIMemoryBudget

    var body: some View {
        let total = Double(budget.gpuCeilingMB)
        guard total > 0 else { return AnyView(EmptyView()) }

        let devFrac = Double(budget.devStackMB) / total
        let ollamaFrac = Double(budget.ollamaModelsMB) / total
        let freeFrac = Double(budget.availableForAIMB) / total

        return AnyView(
            GeometryReader { geo in
                HStack(spacing: 1) {
                    Rectangle()
                        .fill(Color.blue.opacity(0.7))
                        .frame(width: geo.size.width * devFrac)
                    if ollamaFrac > 0.01 {
                        Rectangle()
                            .fill(Color.purple.opacity(0.7))
                            .frame(width: geo.size.width * ollamaFrac)
                    }
                    Rectangle()
                        .fill(Color.green.opacity(0.4))
                        .frame(width: geo.size.width * freeFrac)
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(height: 8)
        )
    }
}

struct BudgetRow: View {
    let label: String
    let valueMB: Int
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(color.opacity(0.7))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Text(formatMB(valueMB))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    private func formatMB(_ mb: Int) -> String {
        mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
    }
}

// MARK: - Can I Run?

struct CanIRunSection: View {
    @ObservedObject var state: AppState
    var onAction: (AppAction) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    SectionLabel("Can I Run AI Models?")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("")
                        .frame(width: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            let installedNames = Set(state.ollamaStatus?.installedModels.map(\.name) ?? [])

            if !expanded {
                // Compact: show top 3 runnable
                let runnable = state.modelResults.filter { $0.feasibility == .runsGreat || $0.feasibility == .runsOk }
                ForEach(runnable.prefix(3), id: \.model.name) { result in
                    ModelRow(result: result, installedNames: installedNames, canInstall: state.ollamaStatus?.isRunning == true, onAction: onAction)
                }
            } else {
                // Privacy note: addresses the natural question after any AI-supply-chain
                // headline ("are these models safe to run?"). Stays factual.
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text("Models run fully offline once downloaded. Weights don't execute code; no data leaves your Mac.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 2)

                // Expanded: all models grouped by feasibility
                let tiers: [(String, [ModelCheckResult])] = [
                    ("Runs Great", state.modelResults.filter { $0.feasibility == .runsGreat }),
                    ("Runs OK", state.modelResults.filter { $0.feasibility == .runsOk }),
                    ("After Cleanup", state.modelResults.filter { $0.feasibility == .afterCleanup }),
                    ("Too Heavy", state.modelResults.filter { $0.feasibility == .tooHeavy }),
                ]

                ForEach(tiers.filter { !$0.1.isEmpty }, id: \.0) { tier in
                    Text(tier.0)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 2)

                    ForEach(tier.1, id: \.model.name) { result in
                        ModelRow(result: result, installedNames: installedNames, canInstall: state.ollamaStatus?.isRunning == true, onAction: onAction)
                    }
                }

            }
        }
        .padding(.bottom, 4)
    }
}

struct ModelRow: View {
    let result: ModelCheckResult
    var installedNames: Set<String> = []
    var canInstall: Bool = true
    var onAction: ((AppAction) -> Void)? = nil
    @State private var isHovered = false
    @State private var showLinks = false
    @State private var copied = false

    private var isInstalled: Bool {
        guard let slug = result.model.ollamaSlug else { return false }
        if installedNames.contains(slug) { return true }
        let base = slug.split(separator: ":").first.map(String.init) ?? slug
        return installedNames.contains { $0.hasPrefix(base + ":") }
    }

    private var statusText: String {
        switch result.feasibility {
        case .runsGreat: return "fits comfortably"
        case .runsOk: return "fits but tight"
        case .afterCleanup: return "fits after cleanup"
        case .tooHeavy: return "too heavy"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if onAction != nil { showLinks.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .font(.system(size: 11))
                        .foregroundStyle(iconColor)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(result.model.name)
                                .font(.system(size: 11))
                                .foregroundStyle(textColor)
                                .lineLimit(1)
                            if isInstalled {
                                Text("installed")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.green.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        HStack(spacing: 6) {
                            Text(result.bestQuant.level)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            if !result.model.lab.isEmpty {
                                Text("·")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                Text(result.model.lab)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            Text(statusText)
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Text(fmtMB(result.bestQuant.ramRequiredMB))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if isHovered, let onAction = onAction, let slug = result.model.ollamaSlug {
                        if canInstall, !isInstalled, result.feasibility != .tooHeavy {
                            Button {
                                onAction(.ollamaPullModel(slug))
                            } label: {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.green)
                            }
                            .buttonStyle(.borderless)
                            .help("ollama pull \(slug)")
                        }
                        if let pullCmd = result.model.ollamaPullCommand {
                            Button {
                                onAction(.copyToClipboard(pullCmd))
                                withAnimation { copied = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation { copied = false }
                                }
                            } label: {
                                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundStyle(copied ? Color.green : Color.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help(copied ? "Copied!" : "Copy: \(pullCmd)")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 3)
                .background(isHovered ? Color.primary.opacity(0.04) : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .onHover { isHovered = $0 }
            .help("\(result.model.name) (\(result.bestQuant.level)) — needs \(result.bestQuant.ramRequiredMB / 1024) GB. Tasks: \(result.model.tasks.joined(separator: ", "))")

            if showLinks, let onAction = onAction {
                VStack(alignment: .leading, spacing: 4) {
                    // Primary action: in-app install when Ollama is running.
                    HStack(spacing: 10) {
                        if canInstall, !isInstalled, result.feasibility != .tooHeavy,
                           let slug = result.model.ollamaSlug {
                            Button {
                                onAction(.ollamaPullModel(slug))
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.system(size: 11))
                                    Text("Install")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundStyle(Color.green)
                            }
                            .buttonStyle(.borderless)
                            .help("Install via Ollama API with live progress")
                        }

                        if let ollamaURL = result.model.ollamaURL {
                            Button {
                                onAction(.openURL(ollamaURL))
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 9))
                                    Text("Open page")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundStyle(.blue)
                            }
                            .buttonStyle(.borderless)
                            .help(ollamaURL)
                        }

                        if let webURL = result.model.websiteURL {
                            Button {
                                onAction(.openURL(webURL))
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 9))
                                    Text("Details")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundStyle(.blue)
                            }
                            .buttonStyle(.borderless)
                        }

                        Spacer()
                    }

                    // Always-visible terminal command, even when Ollama isn't running.
                    if let pullCmd = result.model.ollamaPullCommand {
                        Button {
                            onAction(.copyToClipboard(pullCmd))
                            withAnimation { copied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { copied = false }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.clipboard")
                                    .font(.system(size: 9))
                                    .foregroundStyle(copied ? Color.green : Color.secondary)
                                Text(pullCmd)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(copied ? "(copied)" : "(click to copy)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.borderless)
                        .help("Run in your terminal to download the model")
                    }

                    // License + lab footnote.
                    if !result.model.license.isEmpty || !result.model.lab.isEmpty {
                        Text([result.model.lab, result.model.license].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 38)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.02))
            }
        }
    }

    private var iconName: String {
        switch result.feasibility {
        case .runsGreat: return "checkmark.circle.fill"
        case .runsOk: return "checkmark.circle"
        case .afterCleanup: return "arrow.clockwise.circle"
        case .tooHeavy: return "xmark.circle"
        }
    }

    private var iconColor: Color {
        switch result.feasibility {
        case .runsGreat: return .green
        case .runsOk: return .secondary
        case .afterCleanup: return .orange
        case .tooHeavy: return .gray.opacity(0.4)
        }
    }

    private var textColor: Color {
        result.feasibility == .tooHeavy ? .gray : .primary
    }
}

// MARK: - Actions

struct ActionSection: View {
    @ObservedObject var state: AppState
    var onAction: (AppAction) -> Void

    init(state: AppState, onAction: @escaping (AppAction) -> Void) {
        self.state = state
        self.onAction = onAction
    }

    // Legacy init for backward compat
    init(onAction: @escaping (AppAction) -> Void) {
        self.state = AppState()
        self.onAction = onAction
    }

    var body: some View {
        VStack(spacing: 0) {
            // Auto-optimizer toggle + impact
            HStack(spacing: 8) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(state.autoOptimizerEnabled ? .green : .secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Auto-Optimizer")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                    if state.autoOptimizerEnabled && state.optimizerStats.totalActions > 0 {
                        Text(impactSummary)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { state.autoOptimizerEnabled },
                    set: { _ in onAction(.toggleAutoOptimizer) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)

            // Last action
            if let lastAction = state.optimizerStats.lastAction,
               let lastTime = state.optimizerStats.lastActionTime {
                HStack(spacing: 4) {
                    Text(timeAgo(lastTime))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.quaternary)
                    Text(lastAction)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 44)
                .padding(.bottom, 4)
            }

            // Hybrid routing posture (local-side health for a hybrid stack)
            RoutingPostureRow(state: state)

            // Quick Clean with before/after
            QuickCleanRow(state: state, onAction: onAction)

            ActionRow(icon: "chart.bar.doc.horizontal", label: "RAM Report", shortcut: "M", onAction: { onAction(.showReport) })
            ActionRow(icon: "chart.xyaxis.line", label: "Memory Timeline", shortcut: "T", onAction: { onAction(.showTimeline) })
            ActionRow(icon: "waveform.path.ecg", label: "Babysit Dashboard", shortcut: "B", onAction: { onAction(.showBabysitDashboard) })
            ActionRow(icon: "magnifyingglass", label: "Run Full Check", shortcut: "R", onAction: { onAction(.fullCheck) })
            ActionRow(icon: "wand.and.stars", label: "Run Auto-Fix", shortcut: "F", onAction: { onAction(.autoFix) })

            ActionRow(icon: "bell.badge", label: "Test Weekly Summary", shortcut: "W", onAction: { onAction(.debugWeeklySummary) })
        }
        .padding(.vertical, 4)
    }

    private var impactSummary: String {
        let s = state.optimizerStats
        var parts: [String] = []
        if s.zombiesKilled > 0 { parts.append("\(s.zombiesKilled) zombies killed") }
        if s.memoryFreedMB > 0 { parts.append("\(s.memoryFreedFormatted) freed") }
        if s.chromeWarnings > 0 { parts.append("\(s.chromeWarnings) Chrome alerts") }
        if s.idleServerWarnings > 0 { parts.append("\(s.idleServerWarnings) idle alerts") }
        return parts.joined(separator: " · ")
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
}

struct ActionRow: View {
    let icon: String
    let label: String
    let shortcut: String
    let onAction: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onAction) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer()
                Text("^\(shortcut)")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Footer

struct FooterSection: View {
    @ObservedObject var state: AppState
    var onAction: ((AppAction) -> Void)?

    var body: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        HStack(spacing: 8) {
            Text("DevPulse v\(version)")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
            if state.updateAvailable, let latest = state.latestVersion,
               let url = state.latestReleaseURL {
                Button {
                    onAction?(.openURL(url))
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 8))
                        Text("v\(latest) available")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.borderless)
            }
            Spacer()
            Button {
                onAction?(.openURL("https://github.com/Gdewilde/devpulse"))
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "star")
                        .font(.system(size: 8))
                    Text("Star on GitHub")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            Button {
                onAction?(.openURL("https://devpulse.sh"))
            } label: {
                Text("devpulse.sh")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .padding(.top, 4)
    }
}

// MARK: - Quick Clean

struct QuickCleanRow: View {
    @ObservedObject var state: AppState
    var onAction: (AppAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button {
                onAction(.quickClean)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(state.isCleaningUp ? Color.secondary : Color.green)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(state.isCleaningUp ? "Cleaning..." : "Quick Clean")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                        if let scan = state.cleanupScan, scan.totalReclaimableMB > 0 {
                            Text("\(fmtMB(scan.totalReclaimableMB)) reclaimable")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(state.isCleaningUp)

            // Show last cleanup result
            if let result = state.lastCleanupResult {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                    if result.totalFreedMB > 0 {
                        Text("Freed \(result.freedFormatted)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.green)
                    } else if !result.results.isEmpty {
                        Text("All clean")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.green)
                    } else {
                        Text("Nothing to clean")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(result.results, id: \.action) { r in
                        Text(r.detail)
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary.opacity(0.3), in: Capsule())
                    }
                    Spacer()
                }
                .padding(.horizontal, 44)
                .padding(.bottom, 4)
            }
        }
    }
}

// MARK: - Shared Components

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

// MARK: - Session Profiles

struct SessionProfileSection: View {
    @ObservedObject var state: AppState
    var onAction: (AppAction) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    if let detected = state.detectedProfile {
                        Image(systemName: detected.profile.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                            .frame(width: 14)
                        Text("Session:")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(detected.profile.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                        Text("\(Int(detected.matchScore * 100))%")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    } else {
                        Image(systemName: "person.2")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                        Text("Session Profiles")
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                    }
                    if state.sessionProfileManager.learnModeEnabled {
                        Image(systemName: "brain")
                            .font(.system(size: 8))
                            .foregroundStyle(.purple)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            if let result = state.profileSwitchResult {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                    Text(result)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.green)
                    Spacer()
                }
                .padding(.horizontal, 44)
                .padding(.bottom, 4)
            }

            if expanded {
                HStack {
                    Spacer()
                    Button { onAction(.showSettings) } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 9))
                            Text("Settings")
                                .font(.system(size: 9))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

                if let top = state.learnedPatterns.first {
                    LearnedPatternRow(pattern: top, totalCount: state.learnedPatterns.count, onAction: onAction)
                }

                if let pending = state.pendingSwitchProfile {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Switch to \(pending.name)?")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)

                        if !state.appsToClose.isEmpty {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.red)
                                Text("Will close: \(state.appsToClose.joined(separator: ", "))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !state.appsToLaunch.isEmpty {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.green)
                                Text("Will launch: \(state.appsToLaunch.joined(separator: ", "))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if state.appsToClose.isEmpty && state.appsToLaunch.isEmpty {
                            Text("No changes needed — already matching.")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }

                        HStack(spacing: 8) {
                            Button {
                                onAction(.executeSwitchProfile(pending))
                            } label: {
                                Text("Switch")
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(.blue)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.borderless)
                            .disabled(state.appsToClose.isEmpty && state.appsToLaunch.isEmpty)

                            Button {
                                onAction(.cancelSwitchProfile)
                            } label: {
                                Text("Cancel")
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(.quaternary)
                                    .foregroundStyle(.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }

                if state.pendingSwitchProfile == nil {
                    ForEach(state.sessionProfileManager.profiles) { profile in
                        let isCurrent = state.detectedProfile?.profile.id == profile.id
                            && (state.detectedProfile?.matchScore ?? 0) >= 0.9
                        ProfileRow(
                            profile: profile,
                            estimatedMB: state.sessionProfileManager.estimateMemory(profile),
                            isCurrent: isCurrent,
                            isSwitching: state.isSwitchingProfile,
                            onSwitch: { onAction(.confirmSwitchProfile(profile)) }
                        )
                    }
                }
            }
        }
    }
}

struct LearnedPatternRow: View {
    let pattern: LearnedPattern
    let totalCount: Int
    var onAction: (AppAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain")
                .font(.system(size: 10))
                .foregroundStyle(.purple)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(pattern.suggestedName) — \(pattern.apps.joined(separator: ", "))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                onAction(.acceptLearnedPattern(pattern))
            } label: {
                Text("Add")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.purple.opacity(0.15))
                    .foregroundStyle(.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.borderless)
            Button {
                onAction(.dismissLearnedPattern(pattern))
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

struct ProfileRow: View {
    let profile: SessionProfile
    let estimatedMB: Int
    let isCurrent: Bool
    let isSwitching: Bool
    let onSwitch: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSwitch) {
            HStack(spacing: 8) {
                Image(systemName: profile.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(isCurrent ? .blue : .secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.name)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                    Text("\(profile.apps.joined(separator: ", ")) · ~\(fmtMB(estimatedMB))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.blue)
                } else if isSwitching {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(isCurrent || isSwitching)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Routing Posture Row (v1.5.0)
//
// Surfaces the local-side health of a hybrid AI stack in the menubar.
// Today: local capacity verdict. Future: cloud uptime, recommended
// next-hour routing split.

struct RoutingPostureRow: View {
    @ObservedObject var state: AppState

    /// Reference model size used to grade local capacity:
    /// 20 GB ≈ a typical 32B Q4_K_M, the median local agent target.
    private let referenceModelMB = 20_000

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(verdict.color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hybrid routing")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(verdict.label)
                    .font(.system(size: 13, weight: .medium))
            }

            Spacer()

            Text(verdict.suggestion)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var verdict: Verdict {
        guard let budget = state.aiMemoryBudget else {
            return Verdict(color: .secondary, label: "Capacity unknown", suggestion: "—")
        }
        let prediction = budget.predictLoadImpact(modelSizeMB: referenceModelMB)
        switch prediction {
        case .comfortable:
            return Verdict(color: .green, label: "Local ready", suggestion: "lean local · 70%+")
        case .tight:
            return Verdict(color: .orange, label: "Local tight", suggestion: "balanced · 50/50")
        case .fitsAfterUnload:
            return Verdict(color: .orange, label: "Cleanup needed", suggestion: "auto-clean before lean")
        case .willNotFit:
            return Verdict(color: .red, label: "Local at capacity", suggestion: "lean cloud · <30%")
        }
    }

    struct Verdict {
        let color: Color
        let label: String
        let suggestion: String
    }
}

// MARK: - Actions Enum

enum AppAction {
    case quit(ProcessInfo_Memory)
    case forceQuit(ProcessInfo_Memory)
    case killPids([Int32])
    case showReport
    case showTimeline
    case showBabysitDashboard
    case fullCheck
    case autoFix
    case quickClean
    case restartDockerVM
    case toggleAutoOptimizer
    case openURL(String)
    case chromeTaskManager
    case chromeMemorySaver
    case confirmSwitchProfile(SessionProfile)
    case executeSwitchProfile(SessionProfile)
    case cancelSwitchProfile
    case showSettings
    case addProfile(SessionProfile)
    case deleteProfile(String)
    case updateProfile(SessionProfile)
    case toggleLearnMode
    case acceptLearnedPattern(LearnedPattern)
    case dismissLearnedPattern(LearnedPattern)
    case ollamaUnloadModel(String)
    case ollamaUnloadAll
    case ollamaLoadModel(String)
    case ollamaDeleteModel(String)
    case ollamaDeleteStale
    case ollamaPullModel(String)
    case ollamaCancelPull
    case copyToClipboard(String)
    case killPort(Int32)
    case cleanArtifacts([DevArtifact])
    case debugWeeklySummary
    case quitApp
}

// MARK: - Helpers

private func fmt(_ gb: Double) -> String { String(format: "%.1f GB", gb) }
private func fmtMB(_ mb: Int) -> String {
    mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
}
