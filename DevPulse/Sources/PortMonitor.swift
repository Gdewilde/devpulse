import Foundation

// MARK: - Port Conflict Manager
// Scans listening ports, maps them to processes with project attribution,
// detects conflicts, and provides one-click kill.

struct ListeningPort: Identifiable {
    let id: String  // "pid:port" for uniqueness
    let port: Int
    let pid: Int32
    let processName: String
    let project: String?      // Attributed project from path, if any
    let isDevPort: Bool        // Common dev ports: 3000, 5000, 8080, etc.
    let isSystemConflict: Bool // System service on a dev port (e.g. AirPlay on 5000)

    var displayName: String {
        if let proj = project {
            return "\(processName) (\(proj))"
        }
        return processName
    }
}

struct PortConflict {
    let port: Int
    let holders: [ListeningPort]
    var description: String {
        let names = holders.map(\.displayName).joined(separator: " vs ")
        return ":\(port) — \(names)"
    }
}

struct PortScanResult {
    let ports: [ListeningPort]
    let conflicts: [PortConflict]
    let systemConflicts: [ListeningPort]  // System processes on dev ports

    var hasIssues: Bool { !conflicts.isEmpty || !systemConflicts.isEmpty }
    var devPortCount: Int { ports.filter(\.isDevPort).count }
}

/// Common developer ports
private let commonDevPorts: Set<Int> = [
    3000, 3001, 3002, 3003,  // React, Next.js, Rails
    4000, 4200, 4321,        // Phoenix, Angular, Astro
    5000, 5001, 5173, 5174,  // Flask, Vite
    8000, 8001, 8080, 8081, 8443, // Django, generic HTTP
    8888, 8889,              // Jupyter
    9000, 9090, 9229,        // PHP, Prometheus, Node debug
    11434,                   // Ollama
    1433, 3306, 5432, 6379, 27017, // SQL Server, MySQL, Postgres, Redis, MongoDB
    2181, 9092,              // Zookeeper, Kafka
]

/// Known system services that conflict with dev ports
private let systemPortHogs: [Int: String] = [
    5000: "AirPlay Receiver",
    7000: "AirPlay Receiver",
    5432: "PostgreSQL (system)",
]

/// Scan all listening TCP ports
func scanListeningPorts() -> PortScanResult {
    let pipe = Pipe()
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    proc.arguments = ["-i", "-P", "-n", "-sTCP:LISTEN"]
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice

    do { try proc.run() } catch {
        return PortScanResult(ports: [], conflicts: [], systemConflicts: [])
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()

    guard let output = String(data: data, encoding: .utf8) else {
        return PortScanResult(ports: [], conflicts: [], systemConflicts: [])
    }

    var ports: [ListeningPort] = []
    var seen = Set<String>()

    for line in output.components(separatedBy: "\n").dropFirst() {  // skip header
        guard !line.isEmpty else { continue }
        let cols = line.split(separator: " ", omittingEmptySubsequences: true)
        guard cols.count >= 9 else { continue }

        let processName = String(cols[0])
        let pid = Int32(cols[1]) ?? 0

        // Parse port from NAME column (last): *:3000 or 127.0.0.1:8080
        let nameCol = String(cols.last ?? "")
        guard let colonIdx = nameCol.lastIndex(of: ":") else { continue }
        let portStr = nameCol[nameCol.index(after: colonIdx)...]
        guard let port = Int(portStr) else { continue }

        let uniqueKey = "\(pid):\(port)"
        guard !seen.contains(uniqueKey) else { continue }
        seen.insert(uniqueKey)

        let project = projectForPid(pid)
        let isDev = commonDevPorts.contains(port) || (port >= 3000 && port < 10000)
        let isSystemConflict = systemPortHogs[port] != nil && !isDevProcess(processName)

        ports.append(ListeningPort(
            id: uniqueKey,
            port: port,
            pid: pid,
            processName: processName,
            project: project,
            isDevPort: isDev,
            isSystemConflict: isSystemConflict
        ))
    }

    ports.sort { $0.port < $1.port }

    // Find conflicts: multiple processes on the same port family (e.g., two things on 3000)
    let portGroups = Dictionary(grouping: ports) { $0.port }
    let conflicts = portGroups
        .filter { $0.value.count > 1 }
        .map { PortConflict(port: $0.key, holders: $0.value) }
        .sorted { $0.port < $1.port }

    let systemConflicts = ports.filter(\.isSystemConflict)

    return PortScanResult(
        ports: ports,
        conflicts: conflicts,
        systemConflicts: systemConflicts
    )
}

/// Kill a process by PID (for port release)
func killPortProcess(_ pid: Int32) {
    kill(pid, SIGTERM)
    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
        kill(pid, SIGKILL)
    }
}

// MARK: - Helpers

/// Try to attribute a PID to a project via /proc args or cwd
private func projectForPid(_ pid: Int32) -> String? {
    let pipe = Pipe()
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/bin/ps")
    proc.arguments = ["-p", "\(pid)", "-o", "args="]
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice

    do { try proc.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()

    guard let args = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !args.isEmpty else { return nil }

    // Look for ~/Apps/<project> pattern
    if let range = args.range(of: "/Apps/") {
        let after = args[range.upperBound...]
        let project = after.prefix(while: { $0 != "/" && $0 != " " })
        if !project.isEmpty { return String(project) }
    }

    return nil
}

private func isDevProcess(_ name: String) -> Bool {
    let devNames: Set<String> = [
        "node", "python", "python3", "ruby", "java", "go",
        "cargo", "beam.smp", "php", "uvicorn", "gunicorn",
        "next-server", "webpack", "vite", "esbuild", "nginx",
        "postgres", "mysqld", "redis-server", "mongod",
        "ollama", "Docker", "com.docker"
    ]
    return devNames.contains(name)
}
