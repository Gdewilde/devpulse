import Foundation
import UserNotifications

// MARK: - RAM Advisor
// Tracks memory usage over time, calculates waste, and advises whether
// the user needs more RAM or just needs to optimize.

struct RAMSnapshot: Codable {
    let timestamp: Date
    let usedMB: Int
    let swapMB: Int
    let zombieMB: Int
    let dockerWasteMB: Int
    let electronWasteMB: Int
    let inactiveServerMB: Int
    let totalRAMMB: Int

    init(timestamp: Date, usedMB: Int, swapMB: Int, zombieMB: Int,
         dockerWasteMB: Int = 0, electronWasteMB: Int = 0,
         inactiveServerMB: Int = 0, totalRAMMB: Int) {
        self.timestamp = timestamp
        self.usedMB = usedMB
        self.swapMB = swapMB
        self.zombieMB = zombieMB
        self.dockerWasteMB = dockerWasteMB
        self.electronWasteMB = electronWasteMB
        self.inactiveServerMB = inactiveServerMB
        self.totalRAMMB = totalRAMMB
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        usedMB = try c.decode(Int.self, forKey: .usedMB)
        swapMB = try c.decode(Int.self, forKey: .swapMB)
        zombieMB = try c.decode(Int.self, forKey: .zombieMB)
        dockerWasteMB = try c.decodeIfPresent(Int.self, forKey: .dockerWasteMB) ?? 0
        electronWasteMB = try c.decodeIfPresent(Int.self, forKey: .electronWasteMB) ?? 0
        inactiveServerMB = try c.decodeIfPresent(Int.self, forKey: .inactiveServerMB) ?? 0
        totalRAMMB = try c.decode(Int.self, forKey: .totalRAMMB)
    }
}

struct WasteBreakdown {
    let zombieMB: Int
    let dockerMB: Int
    let electronMB: Int
    let inactiveServerMB: Int
    var totalMB: Int { zombieMB + dockerMB + electronMB + inactiveServerMB }

    /// The biggest waste source name and value, for headline use
    var biggestSource: (name: String, mb: Int)? {
        let sources: [(String, Int)] = [
            ("zombie processes", zombieMB),
            ("Docker overhead", dockerMB),
            ("Electron duplicates", electronMB),
            ("idle dev servers", inactiveServerMB)
        ].filter { $0.1 > 100 }
        return sources.max(by: { $0.1 < $1.1 })
    }
}

struct RAMVerdict {
    let peakUsedGB: Double
    let peakSwapGB: Double
    let totalRAMGB: Double
    let wasteGB: Double
    let optimizedPeakGB: Double
    let snapshotCount: Int
    let daysTracked: Int
    let waste: WasteBreakdown

    enum Rating {
        case plenty
        case fine
        case tight
        case needsMore
    }

    var rating: Rating {
        let ratio = optimizedPeakGB / totalRAMGB
        if ratio < 0.6 { return .plenty }
        if ratio < 0.8 { return .fine }
        if ratio < 0.95 { return .tight }
        return .needsMore
    }

    var headline: String {
        switch rating {
        case .plenty:    return "Plenty of headroom"
        case .fine:      return "RAM is fine"
        case .tight:     return "Tight — optimize first"
        case .needsMore: return "Consider upgrading"
        }
    }

    var detail: String {
        let peakStr = String(format: "%.0f", peakUsedGB)
        let wasteStr = String(format: "%.0f", wasteGB)
        let optimizedStr = String(format: "%.0f", optimizedPeakGB)
        let totalStr = String(format: "%.0f", totalRAMGB)

        var msg: String
        switch rating {
        case .plenty:
            msg = "Peak \(peakStr) GB on \(totalStr) GB Mac. After cleanup: \(optimizedStr) GB. No upgrade needed."
        case .fine:
            msg = "Peak \(peakStr) GB, \(wasteStr) GB recoverable. Optimized: \(optimizedStr) / \(totalStr) GB."
        case .tight:
            msg = "Peak \(peakStr) GB with \(wasteStr) GB waste. Clean up to stay under \(totalStr) GB."
        case .needsMore:
            msg = "Peak \(peakStr) GB with only \(wasteStr) GB waste. Even optimized: \(optimizedStr) / \(totalStr) GB."
        }

        // Add specific advice based on biggest waste source
        if let biggest = waste.biggestSource {
            let bigMB = biggest.mb
            let bigStr = bigMB >= 1024 ? String(format: "%.1f GB", Double(bigMB) / 1024) : "\(bigMB) MB"
            msg += " Biggest: \(bigStr) in \(biggest.name)."
        }

        return msg
    }
}

// MARK: - "Can I Run?" AI Model Database

struct AIModel {
    let name: String
    let parameters: String      // e.g. "7B", "70B"
    let family: String          // e.g. "Llama 3", "Mistral"
    let quantizations: [AIQuantization]
    let tasks: [String]         // e.g. ["chat", "code", "reasoning"]
    let ollamaSlug: String?     // e.g. "llama3.1:8b"
    let websiteSlug: String?    // e.g. "llama3.1-8b"

    var ollamaURL: String? {
        guard let slug = ollamaSlug else { return nil }
        return "https://ollama.com/library/\(slug.split(separator: ":").first ?? Substring(slug))"
    }

    var ollamaPullCommand: String? {
        guard let slug = ollamaSlug else { return nil }
        return "ollama pull \(slug)"
    }

    var websiteURL: String? {
        guard let slug = websiteSlug else { return nil }
        return "https://devpulse.sh/can-i-run/\(slug)"
    }
}

struct AIQuantization {
    let level: String           // e.g. "Q4_K_M", "Q8_0", "FP16"
    let ramRequiredMB: Int
    let quality: String         // "low", "medium", "high", "full"
}

enum ModelFeasibility {
    case runsGreat              // Fits comfortably with headroom
    case runsOk                 // Fits but tight
    case afterCleanup           // Would fit after reclaiming waste
    case tooHeavy               // Doesn't fit even after cleanup
}

struct ModelCheckResult {
    let model: AIModel
    let bestQuant: AIQuantization
    let feasibility: ModelFeasibility
    let availableRAMMB: Int
    let afterCleanupRAMMB: Int
}

/// Database of popular local AI models with RAM requirements.
let aiModelDatabase: [AIModel] = [
    // Llama 3.x family
    AIModel(name: "Llama 3.2 3B", parameters: "3B", family: "Llama", quantizations: [
        AIQuantization(level: "Q4_K_M", ramRequiredMB: 2600, quality: "medium"),
        AIQuantization(level: "Q8_0", ramRequiredMB: 4200, quality: "high"),
    ], tasks: ["chat", "code"], ollamaSlug: "llama3.2:3b", websiteSlug: "llama3.2-3b"),
    AIModel(name: "Llama 3.1 8B", parameters: "8B", family: "Llama", quantizations: [
        AIQuantization(level: "Q4_K_M", ramRequiredMB: 5500, quality: "medium"),
        AIQuantization(level: "Q8_0", ramRequiredMB: 9500, quality: "high"),
    ], tasks: ["chat", "code"], ollamaSlug: "llama3.1:8b", websiteSlug: "llama3.1-8b"),
    AIModel(name: "Llama 3.3 70B", parameters: "70B", family: "Llama", quantizations: [
        AIQuantization(level: "Q4_K_M", ramRequiredMB: 42000, quality: "medium"),
        AIQuantization(level: "Q8_0", ramRequiredMB: 75000, quality: "high"),
    ], tasks: ["chat", "code", "reasoning"], ollamaSlug: "llama3.3:70b", websiteSlug: "llama3.3-70b"),
    AIModel(name: "Llama 4 Scout", parameters: "109B", family: "Llama", quantizations: [
        AIQuantization(level: "Q4_K_M", ramRequiredMB: 65000, quality: "medium"),
    ], tasks: ["chat", "code", "reasoning"], ollamaSlug: "llama4:scout", websiteSlug: "llama4-scout-17b"),

    // Qwen family
    AIModel(name: "Qwen 2.5 7B", parameters: "7B", family: "Qwen", quantizations: [
        AIQuantization(level: "Q4_K_M", ramRequiredMB: 5200, quality: "medium"),
        AIQuantization(level: "Q8_0", ramRequiredMB: 9000, quality: "high"),
    ], tasks: ["chat", "code"], ollamaSlug: "qwen2.5:7b", websiteSlug: nil),
    AIModel(name: "Qwen 2.5 14B", parameters: "14B", family: "Qwen", quantizations: [
        AIQuantization(level: "Q4_K_M", ramRequiredMB: 9500, quality: "medium"),
        AIQuantization(level: "Q8_0", ramRequiredMB: 16000, quality: "high"),
    ], tasks: ["chat", "code"], ollamaSlug: "qwen2.5:14b", websiteSlug: nil),
    AIModel(name: "Qwen 2.5 32B", parameters: "32B", family: "Qwen", quantizations: [
        AIQuantization(level: "Q4_K_M", ramRequiredMB: 20000, quality: "medium"),
        AIQuantization(level: "Q8_0", ramRequiredMB: 36000, quality: "high"),
    ], tasks: ["chat", "code", "reasoning"], ollamaSlug: "qwen2.5:32b", websiteSlug: "qwen2.5-coder-32b"),
    AIModel(name: "Qwen 2.5 72B", parameters: "72B", family: "Qwen", quantizations: [
        AIQuantization(level: "Q4_K_M", ramRequiredMB: 44000, quality: "medium"),
        AIQuantization(level: "Q8_0", ramRequiredMB: 78000, quality: "high"),
    ], tasks: ["chat", "code", "reasoning"], ollamaSlug: "qwen2.5:72b", websiteSlug: nil),
    AIModel(name: "QwQ 32B", parameters: "32B", family: "Qwen", quantizations: [
        AIQuantization(level: "Q4_K_M", ramRequiredMB: 20000, quality: "medium"),
        AIQuantization(level: "Q8_0", ramRequiredMB: 36000, quality: "high"),
    ], tasks: ["reasoning"], ollamaSlug: "qwq:32b", websiteSlug: nil),

    // Mistral family
    AIModel(name: "Mistral 7B", parameters: "7B", family: "Mistral", quantizations: [
        AIQuantization(level: "Q4_K_M", ramRequiredMB: 5200, quality: "medium"),
        AIQuantization(level: "Q8_0", ramRequiredMB: 9000, quality: "high"),
    ], tasks: ["chat", "code"], ollamaSlug: "mistral:7b", websiteSlug: nil),
    AIModel(name: "Mistral Small 24B", parameters: "24B", family: "Mistral", quantizations: [
        AIQuantization(level: "Q4_K_M", ramRequiredMB: 15000, quality: "medium"),
        AIQuantization(level: "Q8_0", ramRequiredMB: 27000, quality: "high"),
    ], tasks: ["chat", "code"], ollamaSlug: "mistral-small:24b", websiteSlug: "mistral-small-3.1-24b"),

    // DeepSeek family
    AIModel(name: "DeepSeek R1 7B", parameters: "7B", family: "DeepSeek", quantizations: [
        AIQuantization(level: "Q4_K_M", ramRequiredMB: 5500, quality: "medium"),
        AIQuantization(level: "Q8_0", ramRequiredMB: 9500, quality: "high"),
    ], tasks: ["reasoning", "code"], ollamaSlug: "deepseek-r1:7b", websiteSlug: nil),
    AIModel(name: "DeepSeek R1 32B", parameters: "32B", family: "DeepSeek", quantizations: [
        AIQuantization(level: "Q4_K_M", ramRequiredMB: 20000, quality: "medium"),
        AIQuantization(level: "Q8_0", ramRequiredMB: 36000, quality: "high"),
    ], tasks: ["reasoning", "code"], ollamaSlug: "deepseek-r1:32b", websiteSlug: "deepseek-r1-distill-32b"),
    AIModel(name: "DeepSeek R1 70B", parameters: "70B", family: "DeepSeek", quantizations: [
        AIQuantization(level: "Q4_K_M", ramRequiredMB: 42000, quality: "medium"),
    ], tasks: ["reasoning", "code"], ollamaSlug: "deepseek-r1:70b", websiteSlug: "deepseek-r1"),

    // Gemma family
    AIModel(name: "Gemma 2 9B", parameters: "9B", family: "Gemma", quantizations: [
        AIQuantization(level: "Q4_K_M", ramRequiredMB: 6500, quality: "medium"),
        AIQuantization(level: "Q8_0", ramRequiredMB: 11000, quality: "high"),
    ], tasks: ["chat", "code"], ollamaSlug: "gemma2:9b", websiteSlug: nil),
    AIModel(name: "Gemma 2 27B", parameters: "27B", family: "Gemma", quantizations: [
        AIQuantization(level: "Q4_K_M", ramRequiredMB: 17000, quality: "medium"),
        AIQuantization(level: "Q8_0", ramRequiredMB: 30000, quality: "high"),
    ], tasks: ["chat", "code"], ollamaSlug: "gemma2:27b", websiteSlug: "gemma3-27b"),

    // Phi family
    AIModel(name: "Phi-4 14B", parameters: "14B", family: "Phi", quantizations: [
        AIQuantization(level: "Q4_K_M", ramRequiredMB: 9500, quality: "medium"),
        AIQuantization(level: "Q8_0", ramRequiredMB: 16000, quality: "high"),
    ], tasks: ["chat", "code", "reasoning"], ollamaSlug: "phi4:14b", websiteSlug: "phi4-14b"),

    // Code-specific
    AIModel(name: "CodeLlama 34B", parameters: "34B", family: "Llama", quantizations: [
        AIQuantization(level: "Q4_K_M", ramRequiredMB: 21000, quality: "medium"),
        AIQuantization(level: "Q8_0", ramRequiredMB: 38000, quality: "high"),
    ], tasks: ["code"], ollamaSlug: "codellama:34b", websiteSlug: nil),
    AIModel(name: "Codestral 22B", parameters: "22B", family: "Mistral", quantizations: [
        AIQuantization(level: "Q4_K_M", ramRequiredMB: 14000, quality: "medium"),
        AIQuantization(level: "Q8_0", ramRequiredMB: 25000, quality: "high"),
    ], tasks: ["code"], ollamaSlug: "codestral:22b", websiteSlug: nil),

    // Starcoder
    AIModel(name: "StarCoder2 15B", parameters: "15B", family: "StarCoder", quantizations: [
        AIQuantization(level: "Q4_K_M", ramRequiredMB: 10000, quality: "medium"),
        AIQuantization(level: "Q8_0", ramRequiredMB: 17000, quality: "high"),
    ], tasks: ["code"], ollamaSlug: "starcoder2:15b", websiteSlug: nil),
]

// MARK: - RAM Advisor Class

class RAMAdvisor {
    private let storePath: URL
    private let weeklyStatePath: URL
    private var snapshots: [RAMSnapshot] = []
    private let maxAge: TimeInterval = 7 * 24 * 3600 // 7 days

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("DevPulse")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storePath = dir.appendingPathComponent("ram-snapshots.json")
        weeklyStatePath = dir.appendingPathComponent("weekly-state.json")
        loadSnapshots()
        requestNotificationPermission()
    }

    // MARK: - Recording

    func recordSnapshot(stats: MemoryStats, zombieMB: Int, dockerWasteMB: Int = 0,
                        electronWasteMB: Int = 0, inactiveServerMB: Int = 0) {
        let snapshot = RAMSnapshot(
            timestamp: Date(),
            usedMB: Int(stats.usedGB * 1024),
            swapMB: Int(stats.swapUsedGB * 1024),
            zombieMB: zombieMB,
            dockerWasteMB: dockerWasteMB,
            electronWasteMB: electronWasteMB,
            inactiveServerMB: inactiveServerMB,
            totalRAMMB: Int(stats.totalGB * 1024)
        )
        snapshots.append(snapshot)
        pruneOld()
        saveSnapshots()
        checkWeeklySummary()
    }

    // MARK: - Verdict

    func getVerdict() -> RAMVerdict? {
        guard !snapshots.isEmpty else { return nil }

        let totalRAMGB = Double(snapshots.last?.totalRAMMB ?? 0) / 1024
        let peakUsedMB = snapshots.map(\.usedMB).max() ?? 0
        let peakSwapMB = snapshots.map(\.swapMB).max() ?? 0

        let count = snapshots.count
        let avgZombieMB = snapshots.map(\.zombieMB).reduce(0, +) / count
        let avgDockerMB = snapshots.map(\.dockerWasteMB).reduce(0, +) / count
        let avgElectronMB = snapshots.map(\.electronWasteMB).reduce(0, +) / count
        let avgInactiveMB = snapshots.map(\.inactiveServerMB).reduce(0, +) / count

        let waste = WasteBreakdown(
            zombieMB: avgZombieMB,
            dockerMB: avgDockerMB,
            electronMB: avgElectronMB,
            inactiveServerMB: avgInactiveMB
        )

        let peakUsedGB = Double(peakUsedMB) / 1024
        let peakSwapGB = Double(peakSwapMB) / 1024
        let wasteGB = Double(waste.totalMB) / 1024
        let optimizedPeakGB = max(peakUsedGB - wasteGB, 0)

        let firstDate = snapshots.first?.timestamp ?? Date()
        let daysTracked = max(1, Int(Date().timeIntervalSince(firstDate) / 86400))

        return RAMVerdict(
            peakUsedGB: peakUsedGB,
            peakSwapGB: peakSwapGB,
            totalRAMGB: totalRAMGB,
            wasteGB: wasteGB,
            optimizedPeakGB: optimizedPeakGB,
            snapshotCount: count,
            daysTracked: daysTracked,
            waste: waste
        )
    }

    // MARK: - "Can I Run?" Checker

    func checkModels() -> [ModelCheckResult] {
        guard let verdict = getVerdict() else { return [] }

        let totalRAMMB = Int(verdict.totalRAMGB * 1024)
        // Available = total RAM minus current non-reclaimable usage
        let currentUsedMB = Int(verdict.peakUsedGB * 1024)
        let availableMB = max(totalRAMMB - currentUsedMB + Int(verdict.wasteGB * 1024), 0)
        let afterCleanupMB = availableMB + verdict.waste.totalMB

        var results: [ModelCheckResult] = []

        for model in aiModelDatabase {
            // Find the best quantization that fits
            let sorted = model.quantizations.sorted { $0.ramRequiredMB < $1.ramRequiredMB }

            for quant in sorted.reversed() {
                let feasibility: ModelFeasibility
                if quant.ramRequiredMB <= availableMB {
                    let headroom = Double(availableMB - quant.ramRequiredMB) / Double(quant.ramRequiredMB)
                    feasibility = headroom > 0.2 ? .runsGreat : .runsOk
                } else if quant.ramRequiredMB <= afterCleanupMB {
                    feasibility = .afterCleanup
                } else {
                    // Try a lower quantization
                    continue
                }

                results.append(ModelCheckResult(
                    model: model,
                    bestQuant: quant,
                    feasibility: feasibility,
                    availableRAMMB: availableMB,
                    afterCleanupRAMMB: afterCleanupMB
                ))
                break
            }

            // If no quant fit, add with lowest quant as tooHeavy
            if !results.contains(where: { $0.model.name == model.name }) {
                if let lowest = sorted.first {
                    results.append(ModelCheckResult(
                        model: model,
                        bestQuant: lowest,
                        feasibility: .tooHeavy,
                        availableRAMMB: availableMB,
                        afterCleanupRAMMB: afterCleanupMB
                    ))
                }
            }
        }

        // Sort: runsGreat first, then runsOk, then afterCleanup, then tooHeavy
        // Within each tier, sort by parameter count descending (biggest model first)
        results.sort { a, b in
            let orderA = feasibilityOrder(a.feasibility)
            let orderB = feasibilityOrder(b.feasibility)
            if orderA != orderB { return orderA < orderB }
            return a.bestQuant.ramRequiredMB > b.bestQuant.ramRequiredMB
        }

        return results
    }

    private func feasibilityOrder(_ f: ModelFeasibility) -> Int {
        switch f {
        case .runsGreat: return 0
        case .runsOk: return 1
        case .afterCleanup: return 2
        case .tooHeavy: return 3
        }
    }

    // MARK: - Weekly Summary Notification

    private struct WeeklyState: Codable {
        var lastNotificationDate: Date
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func checkWeeklySummary() {
        var state = loadWeeklyState()
        let daysSince = Date().timeIntervalSince(state.lastNotificationDate) / 86400
        guard daysSince >= 7 else { return }
        guard let verdict = getVerdict(), verdict.daysTracked >= 3 else { return }

        sendWeeklySummary(verdict: verdict)

        state.lastNotificationDate = Date()
        saveWeeklyState(state)
    }

    /// Force-fire the weekly summary notification, bypassing time and data guards.
    func debugTriggerWeeklySummary() {
        let verdict = getVerdict() ?? RAMVerdict(
            peakUsedGB: 0, peakSwapGB: 0, totalRAMGB: Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024),
            wasteGB: 0, optimizedPeakGB: 0, snapshotCount: 0, daysTracked: 0,
            waste: WasteBreakdown(zombieMB: 0, dockerMB: 0, electronMB: 0, inactiveServerMB: 0)
        )
        sendWeeklySummary(verdict: verdict)
    }

    private func sendWeeklySummary(verdict: RAMVerdict) {
        let peakStr = String(format: "%.0f GB", verdict.peakUsedGB)
        let wasteStr = String(format: "%.0f GB", verdict.wasteGB)

        let content = UNMutableNotificationContent()
        content.title = "DevPulse Weekly Summary"
        content.body = "This week: \(peakStr) peak, \(wasteStr) recoverable waste. \(verdict.headline)."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "devpulse-weekly-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func loadWeeklyState() -> WeeklyState {
        guard let data = try? Data(contentsOf: weeklyStatePath),
              let state = try? JSONDecoder().decode(WeeklyState.self, from: data) else {
            return WeeklyState(lastNotificationDate: Date())
        }
        return state
    }

    private func saveWeeklyState(_ state: WeeklyState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: weeklyStatePath, options: .atomic)
    }

    // MARK: - Persistence

    private func loadSnapshots() {
        guard let data = try? Data(contentsOf: storePath),
              let loaded = try? JSONDecoder().decode([RAMSnapshot].self, from: data) else { return }
        snapshots = loaded
        pruneOld()
    }

    private func saveSnapshots() {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? data.write(to: storePath, options: .atomic)
    }

    private func pruneOld() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        snapshots = snapshots.filter { $0.timestamp > cutoff }
    }
}
