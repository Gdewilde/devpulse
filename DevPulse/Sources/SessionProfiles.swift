import Foundation
import AppKit

// MARK: - Dev Session Profiles (Phase 8)
// Define, detect, and switch between workspace profiles.

struct SessionProfile: Codable, Identifiable, Sendable {
    var id: String
    var name: String
    var apps: [String]          // App display names
    var estimatedRAMGB: Double
    var icon: String            // SF Symbol name
    var isBuiltIn: Bool = true

    static let builtIn: [SessionProfile] = [
        SessionProfile(
            id: "frontend",
            name: "Frontend",
            apps: ["Cursor", "Google Chrome", "Figma"],
            estimatedRAMGB: 12,
            icon: "paintbrush"
        ),
        SessionProfile(
            id: "backend",
            name: "Backend",
            apps: ["Cursor", "Docker", "Postico"],
            estimatedRAMGB: 10,
            icon: "server.rack"
        ),
        SessionProfile(
            id: "fullstack",
            name: "Full Stack",
            apps: ["Cursor", "Google Chrome", "Docker", "Figma"],
            estimatedRAMGB: 18,
            icon: "square.stack.3d.up"
        ),
        SessionProfile(
            id: "light",
            name: "Light",
            apps: ["Google Chrome"],
            estimatedRAMGB: 4,
            icon: "leaf"
        ),
        SessionProfile(
            id: "review",
            name: "Code Review",
            apps: ["Google Chrome", "Slack"],
            estimatedRAMGB: 6,
            icon: "eye"
        ),
    ]

    static let availableIcons: [String] = [
        "paintbrush", "server.rack", "square.stack.3d.up", "leaf", "eye",
        "hammer", "wrench.and.screwdriver", "terminal", "desktopcomputer",
        "bolt", "flame", "star", "heart", "flag", "tag",
        "briefcase", "book", "pencil", "doc.text", "folder",
        "globe", "cloud", "moon", "sun.max", "cup.and.saucer",
    ]
}

struct DetectedProfile {
    let profile: SessionProfile
    let matchScore: Double      // 0.0 to 1.0
    let matchedApps: [String]
    let missingApps: [String]
}

// MARK: - Learning Mode

struct AppSnapshot: Codable {
    let apps: [String]
    let timestamp: Date
}

struct LearnedPattern: Codable, Identifiable {
    let id: String
    let apps: [String]
    let occurrences: Int
    let suggestedName: String
    let suggestedIcon: String
}

class SessionProfileManager {
    private let storePath: URL
    private let snapshotsPath: URL
    private let learnSettingsPath: URL
    private(set) var profiles: [SessionProfile]
    private var snapshots: [AppSnapshot] = []
    var learnModeEnabled: Bool {
        didSet { saveLearnSettings() }
    }

    private static let ignoredApps: Set<String> = [
        "Finder", "DevPulse", "System Preferences", "System Settings",
        "Spotlight", "Notification Center", "Control Center",
        "WindowManager", "universalAccessAuthWarn",
    ]

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("DevPulse")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storePath = dir.appendingPathComponent("profiles.json")
        snapshotsPath = dir.appendingPathComponent("session-snapshots.json")
        learnSettingsPath = dir.appendingPathComponent("learn-settings.json")
        profiles = Self.loadProfiles(from: storePath)
        snapshots = Self.loadSnapshots(from: snapshotsPath)
        learnModeEnabled = Self.loadLearnSetting(from: learnSettingsPath)
    }

    // MARK: - Profile Management

    func addProfile(_ profile: SessionProfile) {
        var p = profile
        p.isBuiltIn = false
        profiles.append(p)
        saveProfiles()
    }

    func updateProfile(_ profile: SessionProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        saveProfiles()
    }

    func deleteProfile(id: String) {
        profiles.removeAll { $0.id == id }
        saveProfiles()
    }

    func resetToDefaults() {
        profiles = SessionProfile.builtIn
        saveProfiles()
    }

    // MARK: - Detection

    func detectCurrentProfile() -> DetectedProfile? {
        let runningApps = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { $0.localizedName }
        )

        var best: DetectedProfile?

        for profile in profiles {
            let profileApps = Set(profile.apps)
            let matched = profileApps.intersection(runningApps)
            let missing = profileApps.subtracting(runningApps)
            let score = profileApps.isEmpty ? 0 : Double(matched.count) / Double(profileApps.count)

            let detected = DetectedProfile(
                profile: profile,
                matchScore: score,
                matchedApps: Array(matched),
                missingApps: Array(missing)
            )

            if score > (best?.matchScore ?? 0) {
                best = detected
            }
        }

        if let b = best, b.matchScore >= 0.5 { return b }
        return nil
    }

    // MARK: - Learning

    func recordSnapshot() {
        guard learnModeEnabled else { return }
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.localizedName }
            .filter { !Self.ignoredApps.contains($0) }
            .sorted()

        guard apps.count >= 2 else { return }

        snapshots.append(AppSnapshot(apps: apps, timestamp: Date()))

        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        snapshots.removeAll { $0.timestamp < cutoff }

        saveSnapshots()
    }

    func detectPatterns() -> [LearnedPattern] {
        guard snapshots.count >= 6 else { return [] }

        var pairCounts: [Set<String>: Int] = [:]
        for snapshot in snapshots {
            let apps = Set(snapshot.apps)
            let appList = Array(apps)
            for i in 0..<appList.count {
                for j in (i+1)..<appList.count {
                    let pair: Set<String> = [appList[i], appList[j]]
                    pairCounts[pair, default: 0] += 1
                    for k in (j+1)..<appList.count {
                        let triple: Set<String> = [appList[i], appList[j], appList[k]]
                        pairCounts[triple, default: 0] += 1
                    }
                }
            }
        }

        let threshold = max(3, snapshots.count * 4 / 10)
        let existingAppSets = Set(profiles.map { Set($0.apps) })

        var patterns: [LearnedPattern] = []
        let frequent = pairCounts
            .filter { $0.value >= threshold && $0.key.count >= 2 }
            .sorted { $0.value > $1.value }

        for (appSet, count) in frequent.prefix(5) {
            if existingAppSets.contains(appSet) { continue }
            if patterns.contains(where: { Set($0.apps).isSuperset(of: appSet) }) { continue }

            let apps = appSet.sorted()
            let name = suggestName(for: apps)
            let icon = suggestIcon(for: apps)

            patterns.append(LearnedPattern(
                id: "learned-\(apps.joined(separator: "-").lowercased().replacingOccurrences(of: " ", with: ""))",
                apps: apps,
                occurrences: count,
                suggestedName: name,
                suggestedIcon: icon
            ))
        }

        return patterns
    }

    func runningAppNames() -> [String] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { $0.localizedName }
            .filter { !Self.ignoredApps.contains($0) }
            .sorted()
    }

    // MARK: - Switching

    func switchTo(_ profile: SessionProfile, completion: @escaping @MainActor (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let runningApps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }

            let profileAppSet = Set(profile.apps)
            let runningNames = Set(runningApps.compactMap { $0.localizedName })

            var quitCount = 0
            for app in runningApps {
                guard let name = app.localizedName else { continue }
                if !profileAppSet.contains(name) && name != "Finder" && name != "DevPulse" {
                    app.terminate()
                    quitCount += 1
                }
            }

            if quitCount > 0 { Thread.sleep(forTimeInterval: 2) }

            var launchCount = 0
            for appName in profile.apps {
                if !runningNames.contains(appName) {
                    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID(for: appName))
                        ?? Self.applicationURL(for: appName) {
                        let config = NSWorkspace.OpenConfiguration()
                        config.activates = false
                        NSWorkspace.shared.openApplication(at: appURL, configuration: config)
                        launchCount += 1
                    }
                }
            }

            let msg = "Switched to \(profile.name): quit \(quitCount), launched \(launchCount)"
            DispatchQueue.main.async { completion(msg) }
        }
    }

    func estimateMemory(_ profile: SessionProfile) -> Int {
        let appMemoryEstimates: [String: Int] = [
            "Google Chrome": 4000,
            "Cursor": 2500,
            "Docker": 3000,
            "Figma": 1500,
            "Slack": 800,
            "Notion": 600,
            "Discord": 500,
            "Spotify": 400,
            "Postico": 200,
        ]
        return profile.apps.reduce(0) { $0 + (appMemoryEstimates[$1] ?? 500) }
    }

    // MARK: - Naming Heuristics

    private func suggestName(for apps: [String]) -> String {
        let devApps: Set<String> = ["Cursor", "Xcode", "VS Code", "IntelliJ IDEA", "PyCharm"]
        let browserApps: Set<String> = ["Google Chrome", "Safari", "Firefox", "Arc"]
        let designApps: Set<String> = ["Figma", "Sketch", "Affinity Designer"]
        let commsApps: Set<String> = ["Slack", "Discord", "Zoom", "Microsoft Teams"]

        let appSet = Set(apps)
        let hasDev = !appSet.isDisjoint(with: devApps)
        let hasBrowser = !appSet.isDisjoint(with: browserApps)
        let hasDesign = !appSet.isDisjoint(with: designApps)
        let hasComms = !appSet.isDisjoint(with: commsApps)
        let hasDocker = appSet.contains("Docker")

        if hasDev && hasDesign { return "Design + Code" }
        if hasDev && hasDocker { return "Dev + Docker" }
        if hasDev && hasBrowser && hasComms { return "Full Workday" }
        if hasDev && hasBrowser { return "Dev + Browser" }
        if hasBrowser && hasComms { return "Meetings" }
        if hasDev { return "Coding" }
        return apps.prefix(2).joined(separator: " + ")
    }

    private func suggestIcon(for apps: [String]) -> String {
        let appSet = Set(apps)
        if appSet.contains("Docker") { return "shippingbox" }
        if !appSet.isDisjoint(with: ["Figma", "Sketch"]) { return "paintbrush" }
        if !appSet.isDisjoint(with: ["Slack", "Discord", "Zoom"]) { return "bubble.left.and.bubble.right" }
        if !appSet.isDisjoint(with: ["Cursor", "Xcode", "VS Code"]) { return "terminal" }
        return "sparkles"
    }

    // MARK: - App Resolution

    private static func bundleID(for appName: String) -> String {
        let knownBundles: [String: String] = [
            "Google Chrome": "com.google.Chrome",
            "Cursor": "com.todesktop.230313mzl4w4u92",
            "Figma": "com.figma.Desktop",
            "Slack": "com.tinyspeck.slackmacgap",
            "Docker": "com.docker.docker",
            "Notion": "notion.id",
            "Discord": "com.hnc.Discord",
            "Spotify": "com.spotify.client",
            "Postico": "at.eggerapps.Postico2",
        ]
        return knownBundles[appName] ?? "com.apple.\(appName)"
    }

    private static func applicationURL(for appName: String) -> URL? {
        let paths = [
            "/Applications/\(appName).app",
            "/Applications/Utilities/\(appName).app",
            NSHomeDirectory() + "/Applications/\(appName).app",
        ]
        return paths.map { URL(fileURLWithPath: $0) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Persistence

    private static func loadProfiles(from path: URL) -> [SessionProfile] {
        if let data = try? Data(contentsOf: path),
           let custom = try? JSONDecoder().decode([SessionProfile].self, from: data) {
            return custom
        }
        return SessionProfile.builtIn
    }

    func saveProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: storePath, options: .atomic)
    }

    private static func loadSnapshots(from path: URL) -> [AppSnapshot] {
        guard let data = try? Data(contentsOf: path),
              let snaps = try? JSONDecoder().decode([AppSnapshot].self, from: data) else { return [] }
        return snaps
    }

    private func saveSnapshots() {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? data.write(to: snapshotsPath, options: .atomic)
    }

    private static func loadLearnSetting(from path: URL) -> Bool {
        guard let data = try? Data(contentsOf: path),
              let val = try? JSONDecoder().decode(Bool.self, from: data) else { return false }
        return val
    }

    private func saveLearnSettings() {
        guard let data = try? JSONEncoder().encode(learnModeEnabled) else { return }
        try? data.write(to: learnSettingsPath, options: .atomic)
    }
}
