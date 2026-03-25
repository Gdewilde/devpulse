import Foundation

struct ProcessInfo_Memory: Identifiable {
    let id: Int32
    let name: String
    let memoryMB: Int
    let childCount: Int
    let pids: [Int32]
    /// If this is a GUI app, the bundle name for graceful quit (e.g., "Google Chrome")
    let appBundleName: String?

    var memoryFormatted: String {
        if memoryMB >= 1024 {
            return String(format: "%.1f GB", Double(memoryMB) / 1024)
        }
        return "\(memoryMB) MB"
    }

    var isHigh: Bool { memoryMB >= 1500 }
    var isElevated: Bool { memoryMB >= 500 }

    var displayName: String {
        if childCount > 1 {
            return "\(name) (\(childCount) procs)"
        }
        return name
    }

    /// Whether this can be gracefully quit via AppleScript
    var canGracefulQuit: Bool { appBundleName != nil }
}

/// Known app families: maps helper/child process name prefixes to a parent app name.
private let appFamilies: [(prefix: String, parent: String)] = [
    ("Cursor Helper", "Cursor"),
    ("Cursor", "Cursor"),
    ("Google Chrome Helper", "Chrome"),
    ("Google Chrome", "Chrome"),
    ("Notion Helper", "Notion"),
    ("Notion", "Notion"),
    ("Slack Helper", "Slack"),
    ("Slack", "Slack"),
    ("Spotify Helper", "Spotify"),
    ("Spotify", "Spotify"),
    ("Claude Helper", "Claude App"),
    ("Claude", "Claude App"),
    ("Postman Helper", "Postman"),
    ("Postman", "Postman"),
    ("1Password Helper", "1Password"),
    ("1Password", "1Password"),
    ("Discord Helper", "Discord"),
    ("Discord", "Discord"),
    ("Figma Helper", "Figma"),
    ("Figma", "Figma"),
]

/// Extract app bundle name from args (e.g., "/Applications/Google Chrome.app/..." → "Google Chrome").
private func extractAppBundleName(from args: String) -> String? {
    // Match /Applications/*.app or ~/Apps/*.app
    guard let range = args.range(of: #"/(Applications|Apps)/[^/]+\.app"#, options: .regularExpression) else {
        return nil
    }
    let match = String(args[range])  // e.g., "/Applications/Google Chrome.app"
    guard let lastSlash = match.lastIndex(of: "/") else { return nil }
    var name = String(match[match.index(after: lastSlash)...])
    if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
    return name.isEmpty ? nil : name
}

/// Extract project name from args path (e.g., "/Users/gj/Apps/unify/..." → "unify").
private func extractProjectName(from args: String) -> String? {
    guard let range = args.range(of: #"/Users/[^/]+/[Aa]pps/([^/]+)"#, options: .regularExpression) else {
        return nil
    }
    let match = String(args[range])
    return match.components(separatedBy: "/").last
}

/// Resolve a process to its app family using name, args, and parent chain.
private func resolveAppFamily(
    name: String,
    args: String,
    ppid: Int32,
    pidNames: [Int32: String],
    pidParents: [Int32: Int32],
    pidArgs: [Int32: String]
) -> String {
    // First: try to identify by .app bundle name in args
    if let bundleName = extractAppBundleName(from: args) {
        for family in appFamilies {
            if bundleName.hasPrefix(family.prefix) {
                return family.parent
            }
        }
        // Known app not in families list — use bundle name directly
        return bundleName
    }

    // Check process name against known app families
    for family in appFamilies {
        if name.hasPrefix(family.prefix) {
            return family.parent
        }
    }

    // Runtime processes: attribute by project directory in args
    let runtimeNames: Set<String> = ["node", "tsserver", "next-router-worker", "doppler", "npm"]
    let baseName = name.components(separatedBy: "[").first?
        .trimmingCharacters(in: .whitespaces) ?? name
    if runtimeNames.contains(baseName) || name.hasPrefix("node") {
        // Check own args for project path
        if let project = extractProjectName(from: args) {
            return project
        }

        // Walk parent chain — check parent args for project path
        var current = ppid
        for _ in 0..<4 {
            guard current > 1 else { break }
            if let parentArgs = pidArgs[current],
               let project = extractProjectName(from: parentArgs) {
                return project
            }
            if let parentName = pidNames[current] {
                for family in appFamilies {
                    if parentName.hasPrefix(family.prefix) {
                        return family.parent
                    }
                }
            }
            current = pidParents[current] ?? 0
        }

        return "node (other)"
    }

    // CLI tools named "claude" (lowercase, not from .app bundle)
    if name == "claude" {
        return "Claude CLI"
    }

    // MCP servers — group together
    if name.hasPrefix("mcp") {
        return "MCP servers"
    }

    return name
}

func getTopProcesses(limit: Int = 8) -> [ProcessInfo_Memory] {
    // Single ps call: rss, pid, ppid, then args (which contains the full command with spaces)
    let pipe = Pipe()
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/ps")
    proc.arguments = ["-Ao", "rss=,pid=,ppid=,args="]
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice

    do {
        try proc.run()
    } catch {
        return []
    }

    // Read BEFORE waiting — otherwise the pipe buffer fills and deadlocks
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    guard let output = String(data: data, encoding: .utf8) else { return [] }

    struct RawProc {
        let rss: Int
        let pid: Int32
        let ppid: Int32
        let name: String
        let args: String
    }

    var rawProcs: [RawProc] = []
    var pidNames: [Int32: String] = [:]
    var pidParents: [Int32: Int32] = [:]
    var pidArgs: [Int32: String] = [:]

    for line in output.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }

        // Split into rss, pid, ppid, and the rest (args with spaces)
        let parts = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count == 4,
              let rss = Int(parts[0]),
              let pid = Int32(parts[1]),
              let ppid = Int32(parts[2]) else { continue }

        let args = String(parts[3])
        // Extract basename from the executable path (first token of args, split by /)
        let execPath = args.components(separatedBy: " ").first ?? args
        let name = execPath.components(separatedBy: "/").last ?? execPath

        pidNames[pid] = name
        pidParents[pid] = ppid
        pidArgs[pid] = args

        let memMB = rss / 1024
        if memMB > 10 && name != "ps" {
            rawProcs.append(RawProc(rss: rss, pid: pid, ppid: ppid, name: name, args: args))
        }
    }

    // Aggregate by app family
    struct AppAggregate {
        var totalMB: Int = 0
        var count: Int = 0
        var maxPid: Int32 = 0
        var pids: [Int32] = []
        var appBundleName: String? = nil
    }

    var aggregates: [String: AppAggregate] = [:]

    for proc in rawProcs {
        let family = resolveAppFamily(
            name: proc.name,
            args: proc.args,
            ppid: proc.ppid,
            pidNames: pidNames,
            pidParents: pidParents,
            pidArgs: pidArgs
        )
        var agg = aggregates[family] ?? AppAggregate()
        let mb = proc.rss / 1024
        agg.totalMB += mb
        agg.count += 1
        agg.pids.append(proc.pid)
        if mb > (aggregates[family]?.totalMB ?? 0) / max(aggregates[family]?.count ?? 1, 1) {
            agg.maxPid = proc.pid
        }
        // Detect GUI app bundle name from args
        if agg.appBundleName == nil, let bundleName = extractAppBundleName(from: proc.args) {
            agg.appBundleName = bundleName
        }
        aggregates[family] = agg
    }

    // Sort by total memory descending, take top N
    let sorted = aggregates.sorted { $0.value.totalMB > $1.value.totalMB }

    return sorted.prefix(limit).map { name, agg in
        ProcessInfo_Memory(
            id: agg.maxPid,
            name: name,
            memoryMB: agg.totalMB,
            childCount: agg.count,
            pids: agg.pids,
            appBundleName: agg.appBundleName
        )
    }
}
