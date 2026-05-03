import Foundation

// MARK: - Smart Cleanups (Phase 4)
// One-click actions that save real memory and disk space.

struct CleanupResult {
    let action: String
    let freedMB: Int
    let detail: String
    let success: Bool
}

struct CleanupScanResult {
    let derivedData: DerivedDataScan
    let spotlightIssues: SpotlightScan
    let dockerCache: DockerCacheScan
    let totalReclaimableMB: Int
}

// MARK: - DerivedData Cleanup

struct DerivedDataProject {
    let name: String
    let path: String
    let sizeMB: Int
    let daysSinceAccess: Int
}

struct DerivedDataScan {
    let totalMB: Int
    let staleProjects: [DerivedDataProject]  // Not built in 30+ days
    let staleMB: Int
}

func scanDerivedData() -> DerivedDataScan {
    let fm = FileManager.default
    let ddPath = fm.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Developer/Xcode/DerivedData").path

    guard let contents = try? fm.contentsOfDirectory(atPath: ddPath) else {
        return DerivedDataScan(totalMB: 0, staleProjects: [], staleMB: 0)
    }

    var totalMB = 0
    var staleProjects: [DerivedDataProject] = []

    for dir in contents {
        guard dir != "ModuleCache.noindex" else { continue }
        let fullPath = "\(ddPath)/\(dir)"

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else { continue }

        let sizeMB = duSizeKB(fullPath) / 1024
        totalMB += sizeMB

        if let attrs = try? fm.attributesOfItem(atPath: fullPath),
           let modDate = attrs[.modificationDate] as? Date {
            let days = Int(Date().timeIntervalSince(modDate) / 86400)
            // Extract project name: "ProjectName-hashstring"
            let name = dir.components(separatedBy: "-").dropLast().joined(separator: "-")
            let displayName = name.isEmpty ? dir : name

            if days >= 30 && sizeMB >= 10 {
                staleProjects.append(DerivedDataProject(
                    name: displayName, path: fullPath, sizeMB: sizeMB, daysSinceAccess: days
                ))
            }
        }
    }

    staleProjects.sort { $0.sizeMB > $1.sizeMB }
    let staleMB = staleProjects.reduce(0) { $0 + $1.sizeMB }

    return DerivedDataScan(totalMB: totalMB, staleProjects: staleProjects, staleMB: staleMB)
}

func cleanDerivedData(projects: [DerivedDataProject]? = nil) -> CleanupResult {
    let scan = scanDerivedData()
    let targets = projects ?? scan.staleProjects

    guard !targets.isEmpty else {
        return CleanupResult(action: "DerivedData", freedMB: 0, detail: "Nothing stale to clean", success: true)
    }

    var freedMB = 0
    var cleaned = 0
    let fm = FileManager.default

    for project in targets {
        do {
            try fm.removeItem(atPath: project.path)
            freedMB += project.sizeMB
            cleaned += 1
        } catch {
            // Skip individual failures
        }
    }

    return CleanupResult(
        action: "DerivedData",
        freedMB: freedMB,
        detail: "Removed \(cleaned) stale projects",
        success: cleaned > 0
    )
}

// MARK: - Spotlight Exclusions

struct SpotlightScan {
    let nodeModulesWithoutIndex: [String]  // node_modules dirs missing .metadata_never_index
    let buildDirsToExclude: [String]       // Build dirs that should be excluded
    let issueCount: Int
}

func scanSpotlightIssues() -> SpotlightScan {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser.path
    let appsDir = "\(home)/Apps"

    var nodeModulesWithoutIndex: [String] = []
    var buildDirsToExclude: [String] = []

    let buildDirNames: Set<String> = ["node_modules", "target", ".build", "dist", ".next", "build", "__pycache__", ".turbo"]

    // Scan ~/Apps for projects
    guard let projects = try? fm.contentsOfDirectory(atPath: appsDir) else {
        return SpotlightScan(nodeModulesWithoutIndex: [], buildDirsToExclude: [], issueCount: 0)
    }

    for project in projects {
        let projectPath = "\(appsDir)/\(project)"
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: projectPath, isDirectory: &isDir), isDir.boolValue else { continue }

        // Check node_modules
        let nmPath = "\(projectPath)/node_modules"
        if fm.fileExists(atPath: nmPath) {
            let indexPath = "\(nmPath)/.metadata_never_index"
            if !fm.fileExists(atPath: indexPath) {
                nodeModulesWithoutIndex.append(nmPath)
            }
        }

        // Check build directories
        for dirName in buildDirNames {
            let buildPath = "\(projectPath)/\(dirName)"
            if fm.fileExists(atPath: buildPath) {
                let indexPath = "\(buildPath)/.metadata_never_index"
                if !fm.fileExists(atPath: indexPath) {
                    buildDirsToExclude.append(buildPath)
                }
            }
        }
    }

    let count = nodeModulesWithoutIndex.count + buildDirsToExclude.count
    return SpotlightScan(
        nodeModulesWithoutIndex: nodeModulesWithoutIndex,
        buildDirsToExclude: buildDirsToExclude,
        issueCount: count
    )
}

func fixSpotlightExclusions() -> CleanupResult {
    let scan = scanSpotlightIssues()
    var fixed = 0
    let fm = FileManager.default

    // Add .metadata_never_index to node_modules
    for path in scan.nodeModulesWithoutIndex {
        let indexPath = "\(path)/.metadata_never_index"
        if fm.createFile(atPath: indexPath, contents: nil) {
            fixed += 1
        }
    }

    // Add .metadata_never_index to build directories
    for path in scan.buildDirsToExclude {
        let indexPath = "\(path)/.metadata_never_index"
        if fm.createFile(atPath: indexPath, contents: nil) {
            fixed += 1
        }
    }

    return CleanupResult(
        action: "Spotlight",
        freedMB: 0,  // Saves CPU, not memory directly
        detail: "Excluded \(fixed) dirs from Spotlight indexing",
        success: fixed > 0
    )
}

// MARK: - Docker Cache Purge

struct DockerCacheScan {
    let buildCacheMB: Int
    let danglingImagesMB: Int
    let totalMB: Int
    let available: Bool
}

func scanDockerCache() -> DockerCacheScan {
    // Check if docker CLI is available
    let whichPipe = Pipe()
    let whichProc = Process()
    whichProc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    whichProc.arguments = ["docker"]
    whichProc.standardOutput = whichPipe
    whichProc.standardError = FileHandle.nullDevice
    do { try whichProc.run() } catch { return DockerCacheScan(buildCacheMB: 0, danglingImagesMB: 0, totalMB: 0, available: false) }
    whichProc.waitUntilExit()
    guard whichProc.terminationStatus == 0 else {
        return DockerCacheScan(buildCacheMB: 0, danglingImagesMB: 0, totalMB: 0, available: false)
    }

    // Get build cache size via docker system df
    let pipe = Pipe()
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = ["docker", "system", "df", "--format", "{{.Type}}\t{{.Size}}\t{{.Reclaimable}}"]
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice

    do { try proc.run() } catch {
        return DockerCacheScan(buildCacheMB: 0, danglingImagesMB: 0, totalMB: 0, available: true)
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()

    guard proc.terminationStatus == 0,
          let output = String(data: data, encoding: .utf8) else {
        return DockerCacheScan(buildCacheMB: 0, danglingImagesMB: 0, totalMB: 0, available: true)
    }

    var buildCacheMB = 0
    var imagesMB = 0

    for line in output.components(separatedBy: "\n") {
        let parts = line.components(separatedBy: "\t")
        guard parts.count >= 3 else { continue }
        let typeName = parts[0]
        let reclaimable = parts[2]

        let mb = parseDockerSize(reclaimable)

        if typeName == "Build Cache" {
            buildCacheMB = mb
        } else if typeName == "Images" {
            imagesMB = mb
        }
    }

    return DockerCacheScan(
        buildCacheMB: buildCacheMB,
        danglingImagesMB: imagesMB,
        totalMB: buildCacheMB + imagesMB,
        available: true
    )
}

func purgeDockerBuildCache() -> CleanupResult {
    let beforeScan = scanDockerCache()

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = ["docker", "builder", "prune", "-f"]
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = FileHandle.nullDevice

    do {
        try proc.run()
        proc.waitUntilExit()
    } catch {
        return CleanupResult(action: "Docker Cache", freedMB: 0, detail: "Failed to run docker builder prune", success: false)
    }

    guard proc.terminationStatus == 0 else {
        return CleanupResult(action: "Docker Cache", freedMB: 0, detail: "docker builder prune failed", success: false)
    }

    return CleanupResult(
        action: "Docker Cache",
        freedMB: beforeScan.buildCacheMB,
        detail: "Purged build cache",
        success: true
    )
}

// MARK: - Quick Clean (All Safe Cleanups)

struct QuickCleanResult {
    let results: [CleanupResult]
    let totalFreedMB: Int
    let beforeMemoryMB: Int
    let afterMemoryMB: Int

    var freedFormatted: String {
        totalFreedMB >= 1024
            ? String(format: "%.1f GB", Double(totalFreedMB) / 1024)
            : "\(totalFreedMB) MB"
    }
}

func runQuickClean(killZombies: Bool = true) -> QuickCleanResult {
    let beforeStats = MemoryStats.current()
    let beforeMB = Int(beforeStats.usedGB * 1024)

    var results: [CleanupResult] = []

    // 1. Clean stale DerivedData
    let ddResult = cleanDerivedData()
    if ddResult.success { results.append(ddResult) }

    // 2. Fix Spotlight exclusions
    let slResult = fixSpotlightExclusions()
    if slResult.success { results.append(slResult) }

    // 3. Purge Docker build cache (if Docker is available)
    let dockerScan = scanDockerCache()
    if dockerScan.available && dockerScan.buildCacheMB > 50 {
        let dockerResult = purgeDockerBuildCache()
        if dockerResult.success { results.append(dockerResult) }
    }

    // 4. Kill zombie processes
    if killZombies {
        let zombies = getZombieProcesses()
        if !zombies.isEmpty {
            let allPids = zombies.flatMap(\.pids)
            let totalMB = zombies.reduce(0) { $0 + $1.totalMB }
            for pid in allPids { kill(pid, SIGTERM) }
            Thread.sleep(forTimeInterval: 2)
            for pid in allPids { kill(pid, SIGKILL) }
            results.append(CleanupResult(
                action: "Zombies",
                freedMB: totalMB,
                detail: "Killed \(allPids.count) zombie processes",
                success: true
            ))
        }
    }

    // Measure after
    Thread.sleep(forTimeInterval: 1)
    let afterStats = MemoryStats.current()
    let afterMB = Int(afterStats.usedGB * 1024)

    let totalFreed = results.reduce(0) { $0 + $1.freedMB }

    return QuickCleanResult(
        results: results,
        totalFreedMB: totalFreed,
        beforeMemoryMB: beforeMB,
        afterMemoryMB: afterMB
    )
}

// MARK: - Dev Artifact Scanner (Extended)
// Scans node_modules, Homebrew, Cargo, Gradle, pip, CocoaPods, Ollama models,
// HuggingFace cache — all the hidden disk hogs.

struct DevArtifact: Identifiable {
    let id: String          // path
    let category: String    // "node_modules", "Homebrew", etc.
    let path: String
    let sizeMB: Int
    let project: String?    // Attributed project name, if applicable
    let daysSinceAccess: Int
    let isStale: Bool       // Not accessed in 30+ days

    var sizeFormatted: String {
        sizeMB >= 1024
            ? String(format: "%.1f GB", Double(sizeMB) / 1024)
            : "\(sizeMB) MB"
    }
}

struct DevArtifactScan {
    let artifacts: [DevArtifact]
    let totalMB: Int
    let staleMB: Int
    let byCategory: [(category: String, totalMB: Int, count: Int)]

    var totalFormatted: String {
        totalMB >= 1024
            ? String(format: "%.1f GB", Double(totalMB) / 1024)
            : "\(totalMB) MB"
    }

    var staleFormatted: String {
        staleMB >= 1024
            ? String(format: "%.1f GB", Double(staleMB) / 1024)
            : "\(staleMB) MB"
    }
}

func scanDevArtifacts() -> DevArtifactScan {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser.path
    var artifacts: [DevArtifact] = []

    // 1. node_modules in ~/Apps
    let appsDir = "\(home)/Apps"
    if let projects = try? fm.contentsOfDirectory(atPath: appsDir) {
        for project in projects {
            let nmPath = "\(appsDir)/\(project)/node_modules"
            if let art = scanDirectory(nmPath, category: "node_modules", project: project) {
                artifacts.append(art)
            }
        }
    }

    // 2. Global caches
    let cacheTargets: [(path: String, category: String)] = [
        ("\(home)/.cache/Homebrew", "Homebrew Cache"),
        ("\(home)/Library/Caches/Homebrew", "Homebrew Cache"),
        ("\(home)/.cargo/registry", "Cargo Registry"),
        ("\(home)/.gradle/caches", "Gradle Cache"),
        ("\(home)/.cache/pip", "pip Cache"),
        ("\(home)/Library/Caches/pip", "pip Cache"),
        ("\(home)/Library/Caches/CocoaPods", "CocoaPods Cache"),
        ("\(home)/.cache/huggingface", "HuggingFace Cache"),
        ("\(home)/.ollama/models", "Ollama Models"),
        ("\(home)/.npm/_cacache", "npm Cache"),
        ("\(home)/.cache/yarn", "Yarn Cache"),
        ("\(home)/Library/Caches/pnpm", "pnpm Cache"),
        ("\(home)/.bun/install/cache", "Bun Cache"),
    ]

    for target in cacheTargets {
        if let art = scanDirectory(target.path, category: target.category, project: nil) {
            artifacts.append(art)
        }
    }

    artifacts.sort { $0.sizeMB > $1.sizeMB }

    let totalMB = artifacts.reduce(0) { $0 + $1.sizeMB }
    let staleMB = artifacts.filter(\.isStale).reduce(0) { $0 + $1.sizeMB }

    // Group by category
    let grouped = Dictionary(grouping: artifacts) { $0.category }
    let byCategory = grouped.map { (category: $0.key, totalMB: $0.value.reduce(0) { $0 + $1.sizeMB }, count: $0.value.count) }
        .sorted { $0.totalMB > $1.totalMB }

    return DevArtifactScan(
        artifacts: artifacts,
        totalMB: totalMB,
        staleMB: staleMB,
        byCategory: byCategory
    )
}

func cleanDevArtifacts(_ artifacts: [DevArtifact]) -> CleanupResult {
    let fm = FileManager.default
    var freedMB = 0
    var cleaned = 0

    for artifact in artifacts {
        do {
            try fm.removeItem(atPath: artifact.path)
            freedMB += artifact.sizeMB
            cleaned += 1
        } catch {
            // Skip individual failures
        }
    }

    return CleanupResult(
        action: "Dev Artifacts",
        freedMB: freedMB,
        detail: "Removed \(cleaned) artifact\(cleaned == 1 ? "" : "s")",
        success: cleaned > 0
    )
}

private func scanDirectory(_ path: String, category: String, project: String?) -> DevArtifact? {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }

    let sizeMB = duSizeKB(path) / 1024
    guard sizeMB >= 10 else { return nil }  // Skip tiny dirs

    let days: Int
    if let attrs = try? fm.attributesOfItem(atPath: path),
       let modDate = attrs[.modificationDate] as? Date {
        days = Int(Date().timeIntervalSince(modDate) / 86400)
    } else {
        days = 0
    }

    return DevArtifact(
        id: path,
        category: category,
        path: path,
        sizeMB: sizeMB,
        project: project,
        daysSinceAccess: days,
        isStale: days >= 30
    )
}

// MARK: - Full Scan

func scanAllCleanups() -> CleanupScanResult {
    let dd = scanDerivedData()
    let sl = scanSpotlightIssues()
    let docker = scanDockerCache()
    let total = dd.staleMB + docker.totalMB

    return CleanupScanResult(
        derivedData: dd,
        spotlightIssues: sl,
        dockerCache: docker,
        totalReclaimableMB: total
    )
}

// MARK: - Helpers

/// Parse Docker size strings like "2.5GB", "500MB", "1.2GB (30%)"
private func parseDockerSize(_ s: String) -> Int {
    // Strip the reclaimable percentage if present: "1.2GB (30%)" → "1.2GB"
    let cleaned = s.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? s

    if cleaned.hasSuffix("GB") {
        let num = Double(cleaned.dropLast(2)) ?? 0
        return Int(num * 1024)
    } else if cleaned.hasSuffix("MB") {
        let num = Double(cleaned.dropLast(2)) ?? 0
        return Int(num)
    } else if cleaned.hasSuffix("kB") {
        return 0
    }
    return 0
}

/// Get directory size in KB using du
private func duSizeKB(_ path: String) -> Int {
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
    return Int(output.split(separator: "\t").first ?? "0") ?? 0
}
