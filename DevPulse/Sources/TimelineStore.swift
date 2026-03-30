import Foundation
import SQLite3
import AppKit

// MARK: - Memory Timeline (Phase 6)
// Stores memory snapshots in SQLite and annotates system events.

struct TimelinePoint {
    let timestamp: Date
    let usedMB: Int
    let swapMB: Int
    let compressedMB: Int
    let topProcess: String
    let topProcessMB: Int
}

struct TimelineEvent {
    let timestamp: Date
    let kind: EventKind
    let detail: String

    enum EventKind: String {
        case appLaunch = "launch"
        case appQuit = "quit"
        case buildStarted = "build"
        case dockerUp = "docker_up"
        case dockerDown = "docker_down"
        case swapCrossing = "swap"
        case zombieKill = "zombie_kill"
        case cleanup = "cleanup"
    }
}

class TimelineStore {
    private var db: OpaquePointer?
    private let dbPath: String
    private var knownRunningApps: Set<String> = []
    private var lastSwapThresholdCrossed: Bool = false
    private var lastDockerRunning: Bool = false

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("DevPulse")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbPath = dir.appendingPathComponent("timeline.sqlite").path
        openDatabase()
        createTables()
        pruneOldData()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Database Setup

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            db = nil
        }
        // WAL mode for better concurrent read/write
        exec("PRAGMA journal_mode=WAL")
    }

    private func createTables() {
        exec("""
            CREATE TABLE IF NOT EXISTS snapshots (
                timestamp REAL PRIMARY KEY,
                used_mb INTEGER,
                swap_mb INTEGER,
                compressed_mb INTEGER,
                top_process TEXT,
                top_process_mb INTEGER
            )
        """)
        exec("""
            CREATE TABLE IF NOT EXISTS events (
                timestamp REAL,
                kind TEXT,
                detail TEXT
            )
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_snapshots_ts ON snapshots(timestamp)")
        exec("CREATE INDEX IF NOT EXISTS idx_events_ts ON events(timestamp)")
    }

    // MARK: - Recording

    func recordSnapshot(stats: MemoryStats, topProcess: ProcessInfo_Memory?) {
        let ts = Date().timeIntervalSince1970
        let usedMB = Int(stats.usedGB * 1024)
        let swapMB = Int(stats.swapUsedGB * 1024)
        let compressedMB = Int(stats.compressedGB * 1024)
        let procName = topProcess?.name ?? ""
        let procMB = topProcess?.memoryMB ?? 0

        exec("""
            INSERT OR REPLACE INTO snapshots VALUES (\(ts), \(usedMB), \(swapMB), \(compressedMB), '\(sanitize(procName))', \(procMB))
        """)
    }

    func recordEvent(_ kind: TimelineEvent.EventKind, detail: String) {
        let ts = Date().timeIntervalSince1970
        exec("INSERT INTO events VALUES (\(ts), '\(kind.rawValue)', '\(sanitize(detail))')")
    }

    // MARK: - Auto-Annotation

    func detectEvents(stats: MemoryStats, dockerRunning: Bool) {
        // Swap threshold crossing (10 GB)
        let swapHigh = stats.swapUsedGB >= 10
        if swapHigh && !lastSwapThresholdCrossed {
            recordEvent(.swapCrossing, detail: String(format: "Swap crossed 10 GB (%.1f GB)", stats.swapUsedGB))
        }
        lastSwapThresholdCrossed = swapHigh

        // Docker up/down
        if dockerRunning && !lastDockerRunning {
            recordEvent(.dockerUp, detail: "Docker Desktop started")
        } else if !dockerRunning && lastDockerRunning {
            recordEvent(.dockerDown, detail: "Docker Desktop stopped")
        }
        lastDockerRunning = dockerRunning

        // App launch/quit detection via NSWorkspace
        detectAppChanges()
    }

    private func detectAppChanges() {
        let runningApps = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { $0.localizedName }
        )

        let launched = runningApps.subtracting(knownRunningApps)
        let quit = knownRunningApps.subtracting(runningApps)

        for app in launched {
            recordEvent(.appLaunch, detail: app)
        }
        for app in quit {
            recordEvent(.appQuit, detail: app)
        }

        knownRunningApps = runningApps
    }

    // MARK: - Queries

    func getSnapshots(hours: Int = 24) -> [TimelinePoint] {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600).timeIntervalSince1970
        var results: [TimelinePoint] = []

        var stmt: OpaquePointer?
        let query = "SELECT timestamp, used_mb, swap_mb, compressed_mb, top_process, top_process_mb FROM snapshots WHERE timestamp > \(cutoff) ORDER BY timestamp"

        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let ts = sqlite3_column_double(stmt, 0)
                let used = Int(sqlite3_column_int(stmt, 1))
                let swap = Int(sqlite3_column_int(stmt, 2))
                let compressed = Int(sqlite3_column_int(stmt, 3))
                let proc = String(cString: sqlite3_column_text(stmt, 4))
                let procMB = Int(sqlite3_column_int(stmt, 5))

                results.append(TimelinePoint(
                    timestamp: Date(timeIntervalSince1970: ts),
                    usedMB: used, swapMB: swap, compressedMB: compressed,
                    topProcess: proc, topProcessMB: procMB
                ))
            }
        }
        sqlite3_finalize(stmt)
        return results
    }

    func getEvents(hours: Int = 24) -> [TimelineEvent] {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600).timeIntervalSince1970
        var results: [TimelineEvent] = []

        var stmt: OpaquePointer?
        let query = "SELECT timestamp, kind, detail FROM events WHERE timestamp > \(cutoff) ORDER BY timestamp"

        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let ts = sqlite3_column_double(stmt, 0)
                let kind = String(cString: sqlite3_column_text(stmt, 1))
                let detail = String(cString: sqlite3_column_text(stmt, 2))

                if let eventKind = TimelineEvent.EventKind(rawValue: kind) {
                    results.append(TimelineEvent(
                        timestamp: Date(timeIntervalSince1970: ts),
                        kind: eventKind,
                        detail: detail
                    ))
                }
            }
        }
        sqlite3_finalize(stmt)
        return results
    }

    /// Get snapshot count and date range for display
    func getStats() -> (count: Int, firstDate: Date?, lastDate: Date?) {
        var count = 0
        var first: Date?
        var last: Date?

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*), MIN(timestamp), MAX(timestamp) FROM snapshots", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
                let firstTs = sqlite3_column_double(stmt, 1)
                let lastTs = sqlite3_column_double(stmt, 2)
                if firstTs > 0 { first = Date(timeIntervalSince1970: firstTs) }
                if lastTs > 0 { last = Date(timeIntervalSince1970: lastTs) }
            }
        }
        sqlite3_finalize(stmt)
        return (count, first, last)
    }

    // MARK: - Export

    func exportAsText(hours: Int = 24) -> String {
        let snapshots = getSnapshots(hours: hours)
        let events = getEvents(hours: hours)

        let df = DateFormatter()
        df.dateFormat = "HH:mm"

        var lines: [String] = ["DevPulse Memory Timeline — Last \(hours)h", ""]

        // Merge snapshots and events by time
        var eventIdx = 0
        let sampleRate = max(snapshots.count / 60, 1) // ~60 rows max

        for (i, snap) in snapshots.enumerated() {
            // Insert events that happened before this snapshot
            while eventIdx < events.count && events[eventIdx].timestamp <= snap.timestamp {
                let e = events[eventIdx]
                lines.append("  \(df.string(from: e.timestamp))  [\(e.kind.rawValue)] \(e.detail)")
                eventIdx += 1
            }

            guard i % sampleRate == 0 else { continue }
            let time = df.string(from: snap.timestamp)
            let bar = String(repeating: "█", count: min(snap.usedMB / 1024, 64))
            lines.append("\(time)  \(String(format: "%2d", snap.usedMB / 1024))G |\(bar)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Maintenance

    private func pruneOldData() {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600).timeIntervalSince1970
        exec("DELETE FROM snapshots WHERE timestamp < \(cutoff)")
        exec("DELETE FROM events WHERE timestamp < \(cutoff)")
    }

    // MARK: - Helpers

    private func exec(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "''")
    }
}
