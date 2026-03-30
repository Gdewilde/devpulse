import Foundation

struct ProcessInfo_Memory: Identifiable {
    let id: Int32
    let name: String
    let memoryMB: Int
    let childCount: Int
    let pids: [Int32]
    /// If this is a GUI app, the bundle name for graceful quit (e.g., "Google Chrome")
    let appBundleName: String?
    /// Breakdown of process types within this group (e.g., ["node": 8, "tsserver": 2])
    let breakdown: [(name: String, count: Int, mb: Int)]

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
            return "\(name) (\(childCount))"
        }
        return name
    }

    /// Short summary like "8 node, 2 tsserver, 1 Cursor"
    /// For Claude CLI: "12 sessions"
    var breakdownSummary: String? {
        if name == "Claude CLI" {
            let sessionCount = breakdown.reduce(0) { $0 + $1.count }
            return "\(sessionCount) sessions"
        }
        guard breakdown.count > 1 else { return nil }
        let top = breakdown.prefix(3)
        let parts = top.map { "\($0.count) \($0.name)" }
        let suffix = breakdown.count > 3 ? " +" : ""
        return parts.joined(separator: ", ") + suffix
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

/// Extract a descriptive label for a Claude CLI session from its args.
/// e.g., "claude --worktree stripe-billing" → "stripe-billing"
///        "claude --permission-mode auto" → "session (auto)"
///        "claude" → nil (will fall back to plain "claude")
private func claudeSessionLabel(name: String, args: String) -> String? {
    guard name == "claude" else { return nil }

    // Check for --worktree flag
    if let range = args.range(of: #"--worktree\s+(\S+)"#, options: .regularExpression) {
        let match = String(args[range])
        let worktree = match.components(separatedBy: .whitespaces).last ?? ""
        if !worktree.isEmpty { return worktree }
    }

    // Try to extract the working directory from /proc or lsof — too expensive.
    // Instead, parse any flags to differentiate sessions.
    let flags = args.components(separatedBy: " ").dropFirst() // drop "claude" itself
    if flags.isEmpty { return "session" }

    // Extract meaningful flags
    var label = "session"
    for (i, flag) in flags.enumerated() {
        if flag == "--permission-mode", i + 1 < flags.count {
            // Not very useful for display, skip
            continue
        }
        if flag == "-p" || flag == "--print" {
            label = "one-shot"
            break
        }
        if flag == "--resume" || flag == "-r" {
            label = "resumed"
            break
        }
        if !flag.hasPrefix("-") && !flag.hasPrefix("/") {
            // Positional arg — might be a prompt or file, use first word
            let short = String(flag.prefix(20))
            label = short
            break
        }
    }

    return label
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
        // Try to identify the session by --worktree or --permission-mode flags
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
    struct SubProcess {
        var count: Int = 0
        var totalMB: Int = 0
    }

    struct AppAggregate {
        var totalMB: Int = 0
        var count: Int = 0
        var maxPid: Int32 = 0
        var pids: [Int32] = []
        var appBundleName: String? = nil
        var subProcesses: [String: SubProcess] = [:]
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
        if agg.appBundleName == nil, let bundleName = extractAppBundleName(from: proc.args) {
            agg.appBundleName = bundleName
        }
        // Track subprocess types — for Claude CLI, use session context as the key
        let subKey = claudeSessionLabel(name: proc.name, args: proc.args) ?? proc.name
        var sub = agg.subProcesses[subKey] ?? SubProcess()
        sub.count += 1
        sub.totalMB += mb
        agg.subProcesses[subKey] = sub
        aggregates[family] = agg
    }

    // Sort by total memory descending, take top N
    let sorted = aggregates.sorted { $0.value.totalMB > $1.value.totalMB }

    return sorted.prefix(limit).map { name, agg in
        // Build breakdown sorted by memory
        let breakdown = agg.subProcesses
            .sorted { $0.value.totalMB > $1.value.totalMB }
            .map { (name: $0.key, count: $0.value.count, mb: $0.value.totalMB) }

        return ProcessInfo_Memory(
            id: agg.maxPid,
            name: name,
            memoryMB: agg.totalMB,
            childCount: agg.count,
            pids: agg.pids,
            appBundleName: agg.appBundleName,
            breakdown: breakdown
        )
    }
}

// MARK: - Inactive Dev Server Detection

struct InactiveServerGroup {
    let project: String
    let processes: [(name: String, pid: Int32, memoryMB: Int)]
    let totalMB: Int
    var pids: [Int32] { processes.map(\.pid) }
}

/// Detect dev servers running for projects not currently open in any IDE.
/// Compares running project-attributed processes against open IDE workspaces.
func getInactiveDevServers() -> [InactiveServerGroup] {
    // Step 1: Find which projects have IDE windows open
    let openProjects = getOpenIDEProjects()

    // Step 2: Find all project-attributed runtime processes
    let pipe = Pipe()
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/ps")
    proc.arguments = ["-Ao", "pid=,ppid=,rss=,args="]
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice

    do { try proc.run() } catch { return [] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    guard let output = String(data: data, encoding: .utf8) else { return [] }

    let devServerNames: Set<String> = [
        "node", "next-router-worker", "vite", "webpack",
        "esbuild", "tsx", "nodemon", "npm", "yarn", "pnpm",
        "cargo", "go", "python3", "python", "ruby", "php",
        "doppler"
    ]

    struct ServerProc {
        let pid: Int32
        let name: String
        let memoryMB: Int
        let project: String
    }

    var servers: [ServerProc] = []

    for line in output.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        let parts = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count == 4,
              let pid = Int32(parts[0]),
              let rss = Int(parts[2]) else { continue }

        let args = String(parts[3])
        let execPath = args.components(separatedBy: " ").first ?? args
        let name = execPath.components(separatedBy: "/").last ?? execPath
        let baseName = name.components(separatedBy: "[").first?.trimmingCharacters(in: .whitespaces) ?? name

        guard devServerNames.contains(baseName) else { continue }

        // Must be attributed to a project
        guard let projRange = args.range(of: #"/Users/[^/]+/[Aa]pps/([^/]+)"#, options: .regularExpression) else { continue }
        let project = String(args[projRange]).components(separatedBy: "/").last ?? "unknown"

        let mb = rss / 1024
        guard mb >= 10 else { continue }

        servers.append(ServerProc(pid: pid, name: baseName, memoryMB: mb, project: project))
    }

    // Step 3: Filter to projects NOT in openProjects
    let inactive = servers.filter { !openProjects.contains($0.project) }

    // Group by project
    var groups: [String: [(name: String, pid: Int32, memoryMB: Int)]] = [:]
    for s in inactive {
        groups[s.project, default: []].append((name: s.name, pid: s.pid, memoryMB: s.memoryMB))
    }

    return groups.map { project, procs in
        InactiveServerGroup(
            project: project,
            processes: procs,
            totalMB: procs.reduce(0) { $0 + $1.memoryMB }
        )
    }.sorted { $0.totalMB > $1.totalMB }
}

/// Detect which projects have open IDE windows (Cursor, VS Code, Xcode).
private func getOpenIDEProjects() -> Set<String> {
    var projects = Set<String>()

    // Check Cursor/VS Code windows via their CLI args (they include workspace path)
    let pipe = Pipe()
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/ps")
    proc.arguments = ["-Ao", "args="]
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice

    do { try proc.run() } catch { return projects }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    guard let output = String(data: data, encoding: .utf8) else { return projects }

    let idePatterns = ["Cursor", "Code", "Xcode"]

    for line in output.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let isIDE = idePatterns.contains { trimmed.contains($0) }
        guard isIDE else { continue }

        if let range = trimmed.range(of: #"/Users/[^/]+/[Aa]pps/([^/]+)"#, options: .regularExpression) {
            let project = String(trimmed[range]).components(separatedBy: "/").last ?? ""
            if !project.isEmpty { projects.insert(project) }
        }
    }

    return projects
}

// MARK: - DerivedData & Build Cache Detection

struct BuildCacheStats {
    let derivedDataMB: Int
    let nodeModulesCacheMB: Int
    let totalMB: Int
    let staleProjects: [(name: String, sizeMB: Int, daysSinceAccess: Int)]
}

/// Check DerivedData and build cache sizes on disk.
/// These aren't in RAM directly but contribute to memory pressure through file caching.
func getBuildCacheStats() -> BuildCacheStats {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser.path

    // DerivedData
    let derivedDataPath = "\(home)/Library/Developer/Xcode/DerivedData"
    var derivedDataMB = 0
    var staleProjects: [(name: String, sizeMB: Int, daysSinceAccess: Int)] = []

    if let contents = try? fm.contentsOfDirectory(atPath: derivedDataPath) {
        for dir in contents {
            guard dir != "ModuleCache.noindex" else { continue }
            let fullPath = "\(derivedDataPath)/\(dir)"
            let sizeMB = directorySize(fullPath) / (1024 * 1024)
            derivedDataMB += sizeMB

            // Check last access time
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let modDate = attrs[.modificationDate] as? Date {
                let days = Int(Date().timeIntervalSince(modDate) / 86400)
                if days >= 30 && sizeMB >= 50 {
                    // Extract project name from DerivedData folder name (format: ProjectName-hash)
                    let name = dir.components(separatedBy: "-").dropLast().joined(separator: "-")
                    staleProjects.append((name: name.isEmpty ? dir : name, sizeMB: sizeMB, daysSinceAccess: days))
                }
            }
        }
    }

    // node_modules cache (~/.npm, ~/.yarn/cache, ~/.pnpm-store)
    var nodeModulesCacheMB = 0
    let cachePaths = [
        "\(home)/.npm/_cacache",
        "\(home)/.yarn/cache",
        "\(home)/.pnpm-store"
    ]
    for path in cachePaths {
        if fm.fileExists(atPath: path) {
            nodeModulesCacheMB += directorySize(path) / (1024 * 1024)
        }
    }

    staleProjects.sort { $0.sizeMB > $1.sizeMB }

    return BuildCacheStats(
        derivedDataMB: derivedDataMB,
        nodeModulesCacheMB: nodeModulesCacheMB,
        totalMB: derivedDataMB + nodeModulesCacheMB,
        staleProjects: Array(staleProjects.prefix(5))
    )
}

/// Fast directory size using du command.
private func directorySize(_ path: String) -> Int {
    let pipe = Pipe()
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/du")
    proc.arguments = ["-sk", path]
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    do { try proc.run() } catch { return 0 }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    guard let output = String(data: data, encoding: .utf8) else { return 0 }
    let kb = Int(output.split(separator: "\t").first ?? "0") ?? 0
    return kb  // returns KB
}

// MARK: - Chrome Intelligence

struct ChromeStats {
    let tabCount: Int
    let windowCount: Int
    let rendererCount: Int
    let rendererMemoryMB: Int
    let gpuMemoryMB: Int
    let extensionCount: Int
    let extensionMemoryMB: Int
    let utilityMemoryMB: Int
    let mainMemoryMB: Int
    let totalMemoryMB: Int

    var avgTabMB: Int {
        guard rendererCount > 0 else { return 0 }
        return rendererMemoryMB / rendererCount
    }

    var summary: String {
        var parts: [String] = []
        if tabCount > 0 { parts.append("\(tabCount) tabs in \(windowCount) windows") }
        if extensionCount > 0 { parts.append("\(extensionCount) extensions") }
        return parts.joined(separator: ", ")
    }
}

/// Get detailed Chrome process breakdown by parsing helper types from args.
func getChromeStats() -> ChromeStats? {
    // Step 1: Get Chrome tab/window count via AppleScript
    var tabCount = 0
    var windowCount = 0

    let tabScript = Process()
    let tabPipe = Pipe()
    tabScript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    tabScript.arguments = ["-e", """
        tell application "System Events" to set isRunning to exists (processes where name is "Google Chrome")
        if not isRunning then return "0,0"
        tell application "Google Chrome"
            set w to count of windows
            set t to 0
            repeat with win in windows
                set t to t + (count of tabs of win)
            end repeat
            return (t as text) & "," & (w as text)
        end tell
        """]
    tabScript.standardOutput = tabPipe
    tabScript.standardError = FileHandle.nullDevice

    do {
        try tabScript.run()
        let data = tabPipe.fileHandleForReading.readDataToEndOfFile()
        tabScript.waitUntilExit()
        if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let parts = output.split(separator: ",")
            if parts.count == 2 {
                tabCount = Int(parts[0]) ?? 0
                windowCount = Int(parts[1]) ?? 0
            }
        }
    } catch {}

    // Step 2: Categorize Chrome helper processes by --type= arg
    let psPipe = Pipe()
    let psProc = Process()
    psProc.executableURL = URL(fileURLWithPath: "/bin/ps")
    psProc.arguments = ["-Ao", "rss=,args="]
    psProc.standardOutput = psPipe
    psProc.standardError = FileHandle.nullDevice

    do { try psProc.run() } catch { return nil }
    let psData = psPipe.fileHandleForReading.readDataToEndOfFile()
    psProc.waitUntilExit()
    guard let psOutput = String(data: psData, encoding: .utf8) else { return nil }

    var rendererCount = 0, rendererKB = 0
    var gpuKB = 0
    var extensionCount = 0, extensionKB = 0
    var utilityKB = 0
    var mainKB = 0
    var totalKB = 0
    var foundChrome = false

    for line in psOutput.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, let rss = Int(parts[0]) else { continue }
        let args = String(parts[1])

        guard args.contains("Google Chrome") || args.contains("chrome") else { continue }
        // Skip non-Chrome things like chromedriver
        guard args.contains("Google Chrome") || args.contains("/Chrome") else { continue }

        foundChrome = true
        totalKB += rss

        if args.contains("--type=renderer") {
            if args.contains("--extension-process") {
                extensionCount += 1
                extensionKB += rss
            } else {
                rendererCount += 1
                rendererKB += rss
            }
        } else if args.contains("--type=gpu-process") {
            gpuKB += rss
        } else if args.contains("--type=utility") {
            utilityKB += rss
        } else if !args.contains("--type=") {
            mainKB += rss
        }
    }

    guard foundChrome else { return nil }

    return ChromeStats(
        tabCount: tabCount,
        windowCount: windowCount,
        rendererCount: rendererCount,
        rendererMemoryMB: rendererKB / 1024,
        gpuMemoryMB: gpuKB / 1024,
        extensionCount: extensionCount,
        extensionMemoryMB: extensionKB / 1024,
        utilityMemoryMB: utilityKB / 1024,
        mainMemoryMB: mainKB / 1024,
        totalMemoryMB: totalKB / 1024
    )
}

// MARK: - Docker Detection

struct DockerStats {
    let vmMemoryMB: Int          // Total memory reserved by Docker VM
    let containerMemoryMB: Int   // Actual memory used by containers
    let containerCount: Int      // Number of running containers
    let isRunning: Bool          // Whether Docker Desktop is running
    let isIdle: Bool             // Running but no containers

    var wasteMB: Int { max(vmMemoryMB - containerMemoryMB, 0) }

    var wasteFormatted: String {
        let mb = wasteMB
        return mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
    }

    var vmFormatted: String {
        vmMemoryMB >= 1024 ? String(format: "%.1f GB", Double(vmMemoryMB) / 1024) : "\(vmMemoryMB) MB"
    }

    var containerFormatted: String {
        containerMemoryMB >= 1024 ? String(format: "%.1f GB", Double(containerMemoryMB) / 1024) : "\(containerMemoryMB) MB"
    }
}

/// Detect Docker Desktop VM memory and actual container usage.
func getDockerStats() -> DockerStats? {
    // Step 1: Find Docker VM processes (com.docker.hyperkit, vms/0/*, Docker Desktop, etc.)
    let psPipe = Pipe()
    let psProc = Process()
    psProc.executableURL = URL(fileURLWithPath: "/bin/ps")
    psProc.arguments = ["-Ao", "rss=,args="]
    psProc.standardOutput = psPipe
    psProc.standardError = FileHandle.nullDevice

    do { try psProc.run() } catch { return nil }
    let psData = psPipe.fileHandleForReading.readDataToEndOfFile()
    psProc.waitUntilExit()
    guard let psOutput = String(data: psData, encoding: .utf8) else { return nil }

    var vmMemoryKB = 0
    var dockerRunning = false
    let dockerProcessPatterns = [
        "com.docker", "Docker Desktop", "docker-desktop",
        "com.apple.virtualization", "vms/0/"
    ]

    for line in psOutput.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, let rss = Int(parts[0]) else { continue }
        let args = String(parts[1])

        for pattern in dockerProcessPatterns {
            if args.contains(pattern) {
                vmMemoryKB += rss
                dockerRunning = true
                break
            }
        }
    }

    guard dockerRunning else { return nil }

    // Step 2: Query docker stats for actual container memory usage
    var containerMemoryMB = 0
    var containerCount = 0

    let dockerPipe = Pipe()
    let dockerProc = Process()
    dockerProc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    dockerProc.arguments = ["docker", "stats", "--no-stream", "--format", "{{.MemUsage}}"]
    dockerProc.standardOutput = dockerPipe
    dockerProc.standardError = FileHandle.nullDevice

    do {
        try dockerProc.run()
        let dockerData = dockerPipe.fileHandleForReading.readDataToEndOfFile()
        dockerProc.waitUntilExit()

        if dockerProc.terminationStatus == 0,
           let dockerOutput = String(data: dockerData, encoding: .utf8) {
            for line in dockerOutput.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                // Format: "123.4MiB / 7.775GiB" — we want the first part
                let parts = trimmed.components(separatedBy: " / ")
                guard let usagePart = parts.first else { continue }
                containerMemoryMB += parseMemoryString(usagePart)
                containerCount += 1
            }
        }
    } catch {
        // docker CLI not available or not running — we still know the VM is up
    }

    let vmMB = vmMemoryKB / 1024
    return DockerStats(
        vmMemoryMB: vmMB,
        containerMemoryMB: containerMemoryMB,
        containerCount: containerCount,
        isRunning: true,
        isIdle: containerCount == 0
    )
}

/// Parse Docker memory strings like "123.4MiB", "1.5GiB", "456KiB"
private func parseMemoryString(_ s: String) -> Int {
    let trimmed = s.trimmingCharacters(in: .whitespaces)
    if trimmed.hasSuffix("GiB") {
        let num = Double(trimmed.dropLast(3)) ?? 0
        return Int(num * 1024)
    } else if trimmed.hasSuffix("MiB") {
        let num = Double(trimmed.dropLast(3)) ?? 0
        return Int(num)
    } else if trimmed.hasSuffix("KiB") {
        let num = Double(trimmed.dropLast(3)) ?? 0
        return Int(num / 1024)
    } else if trimmed.hasSuffix("B") {
        return 0
    }
    return 0
}

// MARK: - Electron Duplicate Detection

struct ElectronStats {
    let appCount: Int              // Number of Electron apps running
    let totalMemoryMB: Int         // Total memory across all Electron apps
    let perRuntimeOverheadMB: Int  // Estimated per-runtime overhead
    let duplicateWasteMB: Int      // Waste from duplicate runtimes (N-1 copies)
    let apps: [(name: String, memoryMB: Int)]
}

/// Detect running Electron apps and estimate duplicate runtime overhead.
/// Each Electron app bundles its own Chromium runtime (~150-300 MB overhead).
/// If you run 5 Electron apps, you're paying that overhead 5 times.
func getElectronStats(processes: [ProcessInfo_Memory]) -> ElectronStats? {
    let electronApps: Set<String> = [
        "Chrome", "Cursor", "Slack", "Discord", "Notion",
        "Figma", "Postman", "1Password", "Claude App",
        "Spotify", "VS Code", "Obsidian", "Linear",
        "Microsoft Teams", "Zoom"
    ]

    // Non-Electron apps in the set above (they use Chromium but aren't "duplicate waste")
    let browserApps: Set<String> = ["Chrome"]

    var electronProcs: [(name: String, memoryMB: Int)] = []

    for proc in processes {
        if electronApps.contains(proc.name) && !browserApps.contains(proc.name) {
            electronProcs.append((name: proc.name, memoryMB: proc.memoryMB))
        }
    }

    guard electronProcs.count >= 2 else { return nil }

    // Estimated Chromium runtime overhead per Electron app: ~200 MB
    let runtimeOverhead = 200
    // First Electron app doesn't count as waste — it's the "base cost"
    let duplicateWaste = (electronProcs.count - 1) * runtimeOverhead

    let totalMB = electronProcs.reduce(0) { $0 + $1.memoryMB }

    return ElectronStats(
        appCount: electronProcs.count,
        totalMemoryMB: totalMB,
        perRuntimeOverheadMB: runtimeOverhead,
        duplicateWasteMB: duplicateWaste,
        apps: electronProcs.sorted { $0.memoryMB > $1.memoryMB }
    )
}

// MARK: - Zombie Detection

struct ZombieGroup {
    let project: String
    let pids: [Int32]
    let totalMB: Int
    let count: Int
    let sampleArgs: String
}

/// Detect orphaned dev processes: node/runtime procs whose parent is launchd (pid 1)
/// and have no controlling terminal — likely leftover from killed terminal sessions.
func getZombieProcesses() -> [ZombieGroup] {
    let pipe = Pipe()
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/ps")
    proc.arguments = ["-Ao", "pid=,ppid=,tty=,rss=,args="]
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice

    do { try proc.run() } catch { return [] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()
    guard let output = String(data: data, encoding: .utf8) else { return [] }

    let zombieNames: Set<String> = [
        "node", "npm", "yarn", "pnpm", "tsx", "ts-node",
        "tsserver", "eslint_d", "prettier",
        "esbuild", "webpack", "vite", "next-router-worker",
        "fswatch", "chokidar", "nodemon",
        "gopls", "rust-analyzer", "sourcekit-lsp", "clangd", "pylsp",
        "doppler"
    ]

    struct OrphanProc {
        let pid: Int32
        let rss: Int
        let args: String
        let project: String
    }

    var orphans: [OrphanProc] = []

    for line in output.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }

        let parts = trimmed.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
        guard parts.count == 5,
              let pid = Int32(parts[0]),
              let ppid = Int32(parts[1]),
              let rss = Int(parts[3]) else { continue }

        let tty = String(parts[2])
        let args = String(parts[4])

        // Zombie criteria: parent is launchd AND no controlling terminal
        guard ppid == 1 && tty == "??" else { continue }

        let execPath = args.components(separatedBy: " ").first ?? args
        let name = execPath.components(separatedBy: "/").last ?? execPath

        let baseName = name.components(separatedBy: "[").first?
            .trimmingCharacters(in: .whitespaces) ?? name
        guard zombieNames.contains(baseName) || baseName == "node" else { continue }

        let mb = rss / 1024
        guard mb >= 5 else { continue }

        // Try to determine project from args
        var project = "unknown"
        if let range = args.range(of: #"/Users/[^/]+/[Aa]pps/([^/]+)"#, options: .regularExpression) {
            let match = String(args[range])
            project = match.components(separatedBy: "/").last ?? "unknown"
        }

        orphans.append(OrphanProc(pid: pid, rss: rss, args: args, project: project))
    }

    // Group by project
    var groups: [String: (pids: [Int32], totalMB: Int, count: Int, sampleArgs: String)] = [:]
    for orphan in orphans {
        var g = groups[orphan.project] ?? (pids: [], totalMB: 0, count: 0, sampleArgs: orphan.args)
        g.pids.append(orphan.pid)
        g.totalMB += orphan.rss / 1024
        g.count += 1
        groups[orphan.project] = g
    }

    return groups.map { project, g in
        ZombieGroup(project: project, pids: g.pids, totalMB: g.totalMB, count: g.count, sampleArgs: g.sampleArgs)
    }.sorted { $0.totalMB > $1.totalMB }
}
