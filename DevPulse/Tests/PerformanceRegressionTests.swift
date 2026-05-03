import XCTest
@testable import DevPulse

/// Guards against re-introducing the two performance regressions that were
/// fixed after they shipped:
///
/// 1. `refreshData()` ran `du -sk` over node_modules / Ollama models / caches /
///    DerivedData every 60s, pegging a thread at 100% CPU continuously.
///
/// 2. `recordSnapshot()` and `detectPatterns()` ran on the main thread every
///    refresh, JSON-encoding the full snapshot history to disk and running
///    O(n^3) work — stalling the popover for ~10s when opened.
final class PerformanceRegressionTests: XCTestCase {

    // MARK: - Throttle gates (regressions ride in here when someone "tunes" the constants)

    func testDiskScanIntervalStaysThrottled() {
        XCTAssertGreaterThanOrEqual(
            PerformanceTuning.diskScanInterval, 1800,
            """
            Lowering diskScanInterval re-introduces sustained ~100% CPU. \
            scanDevArtifacts/scanAllCleanups shell out to `du -sk` over \
            node_modules, ~/.ollama/models, HuggingFace/Cargo/Gradle caches, \
            and Xcode DerivedData. Each call walks millions of inodes. \
            Keep this >= 30 minutes.
            """
        )
    }

    func testProfileLearningIntervalStaysThrottled() {
        XCTAssertGreaterThanOrEqual(
            PerformanceTuning.profileLearningInterval, 300,
            """
            Lowering profileLearningInterval re-introduces ~10s popover stalls. \
            recordSnapshot() JSON-encodes the full multi-day history and \
            atomically writes it to disk; detectPatterns() is O(n^3) over \
            running apps per snapshot. Keep this >= 5 minutes.
            """
        )
    }

    // MARK: - detectPatterns must stay bounded even with a full history

    func testDetectPatternsIsFastOnRealisticHistory() {
        // detectPatterns is O(snapshots * apps^3) but the inner cost should be
        // dominated by simple String-key dict ops, NOT Set<String> hashing.
        // A regression to Set<String> keys (the original bug) blows runtime up
        // by ~50x and gets caught here.
        let manager = SessionProfileManager()
        // SessionProfileManager.init loads the user's real history from disk;
        // clear it so the test measures only the synthetic input.
        manager.snapshots = []
        let apps = (1...20).map { "App\($0)" }
        // 7 days at one snapshot per 5 min ≈ 2000 — realistic upper bound.
        for _ in 0..<2000 {
            manager.snapshots.append(AppSnapshot(apps: apps, timestamp: Date()))
        }

        let start = Date()
        _ = manager.detectPatterns()
        let elapsed = Date().timeIntervalSince(start)

        // Even in debug mode this runs in well under a second after the
        // Set<String> → String key fix. Pre-fix it took 30+ seconds.
        XCTAssertLessThan(
            elapsed, 5.0,
            "detectPatterns() took \(elapsed)s — likely regressed back to Set<String> dict keys."
        )
    }

    // MARK: - The disk scans are expensive — make sure no callsite invokes them on main

    func testRefreshDataDoesNotRunDiskScansEveryRefresh() {
        // Static check: the interval gate must dominate. We don't have a way to
        // observe AppDelegate directly without launching the app, so this asserts
        // the contract that the gate exists and is large.
        XCTAssertGreaterThan(
            PerformanceTuning.diskScanInterval,
            60,
            "diskScanInterval must be far larger than the refresh interval (15s) so disk scans are gated, not piggybacked on every refresh."
        )
    }
}
