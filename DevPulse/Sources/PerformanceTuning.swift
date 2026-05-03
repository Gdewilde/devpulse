import Foundation

/// Tunable intervals for background work. These exist to throttle expensive
/// operations that previously caused 100% CPU and main-thread stalls.
///
/// Lowering these values has caused real regressions — see PerformanceRegressionTests.
enum PerformanceTuning {
    /// Gate for `du -sk` scans on node_modules, Ollama models, caches, DerivedData.
    /// Running these every minute pegged a thread at 100% CPU continuously.
    static let diskScanInterval: TimeInterval = 1800 // 30 min

    /// Gate for `recordSnapshot()` (writes full history JSON to disk) and
    /// `detectPatterns()` (O(n^3) over running apps per snapshot).
    /// Running these every refresh stalled the main thread for ~10s when
    /// the popover was opened.
    static let profileLearningInterval: TimeInterval = 300 // 5 min
}
