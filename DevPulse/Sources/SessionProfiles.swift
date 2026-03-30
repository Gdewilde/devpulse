import Foundation
import AppKit

// MARK: - Dev Session Profiles (Phase 8)
// Define, detect, and switch between workspace profiles.

struct SessionProfile: Codable, Identifiable {
    let id: String
    let name: String
    let apps: [String]          // App bundle names to launch
    let estimatedRAMGB: Double
    let icon: String            // SF Symbol name

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
}

struct DetectedProfile {
    let profile: SessionProfile
    let matchScore: Double      // 0.0 to 1.0
    let matchedApps: [String]
    let missingApps: [String]
}

class SessionProfileManager {
    private let storePath: URL
    private(set) var profiles: [SessionProfile]

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("DevPulse")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storePath = dir.appendingPathComponent("profiles.json")
        profiles = Self.loadProfiles(from: storePath)
    }

    // MARK: - Detection

    /// Detect which profile best matches currently running apps.
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

        // Only return if match > 50%
        if let b = best, b.matchScore >= 0.5 { return b }
        return nil
    }

    // MARK: - Switching

    /// Switch to a profile: quit apps not in the profile, launch missing ones.
    func switchTo(_ profile: SessionProfile, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let runningApps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }

            let profileAppSet = Set(profile.apps)
            let runningNames = Set(runningApps.compactMap { $0.localizedName })

            // Quit apps not in the target profile (gracefully)
            var quitCount = 0
            for app in runningApps {
                guard let name = app.localizedName else { continue }
                if !profileAppSet.contains(name) && name != "Finder" && name != "DevPulse" {
                    app.terminate()
                    quitCount += 1
                }
            }

            // Wait for quits to process
            if quitCount > 0 { Thread.sleep(forTimeInterval: 2) }

            // Launch missing apps
            var launchCount = 0
            for appName in profile.apps {
                if !runningNames.contains(appName) {
                    let script = "tell application \"\(appName)\" to activate"
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                    proc.arguments = ["-e", script]
                    proc.standardOutput = FileHandle.nullDevice
                    proc.standardError = FileHandle.nullDevice
                    try? proc.run()
                    proc.waitUntilExit()
                    launchCount += 1
                }
            }

            let msg = "Switched to \(profile.name): quit \(quitCount), launched \(launchCount)"
            DispatchQueue.main.async { completion(msg) }
        }
    }

    /// Estimate memory for a profile based on typical app sizes.
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
}
