import Foundation
import Combine

/// Shared observable state for the SwiftUI popover view.
class AppState: ObservableObject {
    @Published var stats = MemoryStats.current()
    @Published var processes: [ProcessInfo_Memory] = []
    @Published var zombies: [ZombieGroup] = []
    @Published var dockerStats: DockerStats? = nil
    @Published var electronStats: ElectronStats? = nil
    @Published var chromeStats: ChromeStats? = nil
    @Published var inactiveServers: [InactiveServerGroup] = []
    @Published var verdict: RAMVerdict? = nil
    @Published var modelResults: [ModelCheckResult] = []
    @Published var swapTrend: SwapTrend = .stable

    enum SwapTrend: String {
        case rising = "↑"
        case falling = "↓"
        case stable = ""
    }

    @Published var autoOptimizerEnabled: Bool = true
    @Published var optimizerStats: OptimizerImpact = OptimizerImpact()

struct OptimizerImpact {
    var zombiesKilled: Int = 0
    var memoryFreedMB: Int = 0
    var chromeWarnings: Int = 0
    var idleServerWarnings: Int = 0
    var lastAction: String? = nil
    var lastActionTime: Date? = nil

    var totalActions: Int { zombiesKilled + chromeWarnings + idleServerWarnings }

    var memoryFreedFormatted: String {
        memoryFreedMB >= 1024
            ? String(format: "%.1f GB", Double(memoryFreedMB) / 1024)
            : "\(memoryFreedMB) MB"
    }
}

    @Published var gpuMemory: GPUMemoryInfo? = nil
    @Published var ollamaStatus: OllamaStatus? = nil
    @Published var aiMemoryBudget: AIMemoryBudget? = nil
    @Published var portScan: PortScanResult? = nil
    @Published var devArtifactScan: DevArtifactScan? = nil
    @Published var appRecommendations: [AppRecommendation] = []
    @Published var ssdHealth: SSDHealth? = nil
    @Published var cleanupScan: CleanupScanResult? = nil
    @Published var lastCleanupResult: QuickCleanResult? = nil
    @Published var isCleaningUp: Bool = false

    // Session Profiles
    let sessionProfileManager = SessionProfileManager()
    @Published var detectedProfile: DetectedProfile? = nil
    @Published var isSwitchingProfile: Bool = false
    @Published var profileSwitchResult: String? = nil
    @Published var pendingSwitchProfile: SessionProfile? = nil
    @Published var appsToClose: [String] = []
    @Published var appsToLaunch: [String] = []
    @Published var learnedPatterns: [LearnedPattern] = []

    // Update check
    @Published var latestVersion: String? = nil
    @Published var latestReleaseURL: String? = nil

    var updateAvailable: Bool {
        guard let latest = latestVersion else { return false }
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return latest.compare(current, options: .numeric) == .orderedDescending
    }

    private var previousSwapGB: Double? = nil

    func updateSwapTrend() {
        let current = stats.swapUsedGB
        if let prev = previousSwapGB {
            let delta = current - prev
            if delta > 0.5 { swapTrend = .rising }
            else if delta < -0.5 { swapTrend = .falling }
            else { swapTrend = .stable }
        }
        previousSwapGB = current
    }
}
