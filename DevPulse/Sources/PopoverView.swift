import SwiftUI

// MARK: - Main Popover

struct PopoverView: View {
    @ObservedObject var state: AppState
    var onAction: (AppAction) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HeaderSection(state: state)

                if state.verdict != nil {
                    VerdictCard(state: state)
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

                if !state.modelResults.isEmpty {
                    Divider().padding(.horizontal, 16)
                    CanIRunSection(state: state, onAction: onAction)
                }

                Divider().padding(.horizontal, 16)
                ActionSection(state: state, onAction: onAction)

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

                FooterSection(onAction: onAction)
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
            }
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
                        : "\(docker.containerCount) containers using \(docker.containerFormatted)"
                )
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

    var body: some View {
        if let verdict = state.verdict {
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
            .background(cardBackground(verdict))
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
                    SectionLabel("Can I Run?")
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

            if !expanded {
                // Compact: show top 3 runnable
                let runnable = state.modelResults.filter { $0.feasibility == .runsGreat || $0.feasibility == .runsOk }
                ForEach(runnable.prefix(3), id: \.model.name) { result in
                    ModelRow(result: result)
                }
            } else {
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
                        ModelRow(result: result)
                    }
                }

                // Ollama / LM Studio links
                HStack(spacing: 12) {
                    Button("Get Ollama") { onAction(.openURL("https://ollama.com/download")) }
                    Button("Get LM Studio") { onAction(.openURL("https://lmstudio.ai")) }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.blue)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .padding(.bottom, 4)
    }
}

struct ModelRow: View {
    let result: ModelCheckResult

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 9))
                .foregroundStyle(iconColor)
                .frame(width: 14)
            Text(result.model.name)
                .font(.system(size: 11))
                .foregroundStyle(textColor)
                .lineLimit(1)
            Spacer()
            Text(result.bestQuant.level)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text("\(result.bestQuant.ramRequiredMB / 1024)G")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .help("\(result.model.name) (\(result.bestQuant.level)) — needs \(result.bestQuant.ramRequiredMB / 1024) GB. Tasks: \(result.model.tasks.joined(separator: ", "))")
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

            // Quick Clean with before/after
            QuickCleanRow(state: state, onAction: onAction)

            ActionRow(icon: "chart.bar.doc.horizontal", label: "RAM Report", shortcut: "M", onAction: { onAction(.showReport) })
            ActionRow(icon: "magnifyingglass", label: "Run Full Check", shortcut: "R", onAction: { onAction(.fullCheck) })
            ActionRow(icon: "wand.and.stars", label: "Run Auto-Fix", shortcut: "F", onAction: { onAction(.autoFix) })
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
    var onAction: ((AppAction) -> Void)?

    var body: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        HStack(spacing: 8) {
            Text("DevPulse v\(version)")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
            Spacer()
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

// MARK: - Actions Enum

enum AppAction {
    case quit(ProcessInfo_Memory)
    case forceQuit(ProcessInfo_Memory)
    case killPids([Int32])
    case showReport
    case fullCheck
    case autoFix
    case quickClean
    case toggleAutoOptimizer
    case openURL(String)
    case chromeTaskManager
    case chromeMemorySaver
    case quitApp
}

// MARK: - Helpers

private func fmt(_ gb: Double) -> String { String(format: "%.1f GB", gb) }
private func fmtMB(_ mb: Int) -> String {
    mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
}
