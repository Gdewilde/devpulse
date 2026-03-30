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
