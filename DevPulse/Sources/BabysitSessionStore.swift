import Foundation

/// Reads and writes babysit session logs at the standard path:
///   ~/Library/Application Support/DevPulse/babysit/session-<ISO>.ndjson
///
/// Each line is a JSON object — a `started`, `tick`, `cleanup`, or `done` event.
/// The CLI writes here automatically when `devpulse babysit` runs; the Babysit
/// Dashboard reads from here to render session history.
enum BabysitSessionStore {

    static let directory: URL = {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("DevPulse").appendingPathComponent("babysit")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Writer (used by CLI)

    /// Build a fresh session log URL for `now`. Filename format:
    /// `session-2026-05-04T01-20-00Z.ndjson`. Colons replaced with dashes
    /// because Finder dislikes them in display.
    static func newSessionLogURL(startedAt: Date = Date()) -> URL {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let stamp = f.string(from: startedAt).replacingOccurrences(of: ":", with: "-")
        return directory.appendingPathComponent("session-\(stamp).ndjson")
    }

    /// Open or create the file handle for appending.
    static func openSessionLog(at url: URL) -> FileHandle? {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil)
        }
        let handle = try? FileHandle(forWritingTo: url)
        try? handle?.seekToEnd()
        return handle
    }

    // MARK: - Reader (used by the dashboard)

    struct Session: Identifiable {
        let id: String           // filename without extension
        let url: URL
        let startedAt: Date?
        let endedAt: Date?
        let interval: Int        // seconds
        let targetFreeMB: Int
        let durationMin: Int?
        let ticks: Int
        let cleanupRuns: Int
        let totalReclaimedMB: Int
        let events: [Event]      // parsed in order

        var elapsed: TimeInterval? {
            guard let s = startedAt, let e = endedAt else { return nil }
            return e.timeIntervalSince(s)
        }

        /// Quick formatted summary string for the list row.
        var summaryLine: String {
            let recl = totalReclaimedMB >= 1024
                ? String(format: "%.1f GB", Double(totalReclaimedMB) / 1024)
                : "\(totalReclaimedMB) MB"
            return "\(ticks) ticks · \(cleanupRuns) cleanups · \(recl) reclaimed"
        }
    }

    struct Event: Identifiable {
        let id = UUID()
        let timestamp: Date
        let kind: String         // "started" | "tick" | "cleanup" | "done"
        let raw: [String: Any]   // for detail view

        // Accessors common across event kinds
        var availableForAIMB: Int? { raw["availableForAIMB"] as? Int }
        var swapGB: Double? { raw["swapGB"] as? Double }
        var memUsedPercent: Int? { raw["memUsedPercent"] as? Int }
        var batteryPercent: Int? { raw["batteryPercent"] as? Int }
        var pressure: String? { raw["pressure"] as? String }
        var reclaimedMB: Int? { raw["reclaimedMB"] as? Int }
        var actions: [String] { raw["actions"] as? [String] ?? [] }
    }

    /// List all sessions, newest first.
    static func listSessions() -> [Session] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }

        return urls
            .filter { $0.pathExtension == "ndjson" }
            .compactMap { loadSession(from: $0) }
            .sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
    }

    /// Parse a single session file into a structured Session.
    static func loadSession(from url: URL) -> Session? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatterPlain = ISO8601DateFormatter()
        formatterPlain.formatOptions = [.withInternetDateTime]

        var events: [Event] = []
        var startedEvent: [String: Any]?
        var doneEvent: [String: Any]?
        var firstTickTime: Date?
        var lastTickTime: Date?
        var ticks = 0
        var cleanupRuns = 0
        var totalReclaimed = 0

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let kind = obj["event"] as? String ?? "unknown"
            let tsStr = obj["ts"] as? String ?? ""
            let ts = formatter.date(from: tsStr) ?? formatterPlain.date(from: tsStr) ?? Date()

            events.append(Event(timestamp: ts, kind: kind, raw: obj))

            switch kind {
            case "started":
                startedEvent = obj
                if firstTickTime == nil { firstTickTime = ts }
            case "tick":
                ticks += 1
                if firstTickTime == nil { firstTickTime = ts }
                lastTickTime = ts
            case "cleanup":
                cleanupRuns += 1
                if let r = obj["reclaimedMB"] as? Int { totalReclaimed += r }
                lastTickTime = ts
            case "done":
                doneEvent = obj
                lastTickTime = ts
            default: break
            }
        }

        let id = url.deletingPathExtension().lastPathComponent
        return Session(
            id: id,
            url: url,
            startedAt: firstTickTime,
            endedAt: doneEvent != nil ? lastTickTime : (events.isEmpty ? nil : lastTickTime),
            interval: startedEvent?["intervalSec"] as? Int ?? 30,
            targetFreeMB: startedEvent?["targetFreeMB"] as? Int ?? 0,
            durationMin: startedEvent?["durationMin"] as? Int,
            ticks: ticks,
            cleanupRuns: cleanupRuns,
            totalReclaimedMB: totalReclaimed,
            events: events
        )
    }

    /// Delete a session file. Used by the dashboard's contextual delete action.
    static func deleteSession(_ session: Session) {
        try? FileManager.default.removeItem(at: session.url)
    }
}
