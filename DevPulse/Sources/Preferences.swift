import Foundation
import ServiceManagement

// MARK: - App Preferences (persisted to UserDefaults)

class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    // MARK: - General

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "launchAtLogin")
            updateLoginItem()
        }
    }

    @Published var refreshIntervalSec: Int {
        didSet { defaults.set(refreshIntervalSec, forKey: "refreshIntervalSec") }
    }

    @Published var showPercentInMenuBar: Bool {
        didSet { defaults.set(showPercentInMenuBar, forKey: "showPercentInMenuBar") }
    }

    @Published var showSwapInMenuBar: Bool {
        didSet { defaults.set(showSwapInMenuBar, forKey: "showSwapInMenuBar") }
    }

    // MARK: - Notifications

    @Published var notifyZombies: Bool {
        didSet { defaults.set(notifyZombies, forKey: "notifyZombies") }
    }

    @Published var notifyMemoryPressure: Bool {
        didSet { defaults.set(notifyMemoryPressure, forKey: "notifyMemoryPressure") }
    }

    @Published var memoryPressureThresholdPct: Int {
        didSet { defaults.set(memoryPressureThresholdPct, forKey: "memoryPressureThresholdPct") }
    }

    @Published var notifySwapGrowth: Bool {
        didSet { defaults.set(notifySwapGrowth, forKey: "notifySwapGrowth") }
    }

    // MARK: - Auto-Optimizer

    @Published var optimizerIntervalMin: Int {
        didSet { defaults.set(optimizerIntervalMin, forKey: "optimizerIntervalMin") }
    }

    @Published var zombieMinAgeMin: Int {
        didSet { defaults.set(zombieMinAgeMin, forKey: "zombieMinAgeMin") }
    }

    @Published var chromeWarnGB: Double {
        didSet { defaults.set(chromeWarnGB, forKey: "chromeWarnGB") }
    }

    @Published var autoKillZombies: Bool {
        didSet { defaults.set(autoKillZombies, forKey: "autoKillZombies") }
    }

    // MARK: - Learning

    @Published var learnSnapshotIntervalMin: Int {
        didSet { defaults.set(learnSnapshotIntervalMin, forKey: "learnSnapshotIntervalMin") }
    }

    @Published var learnExcludedApps: [String] {
        didSet { defaults.set(learnExcludedApps, forKey: "learnExcludedApps") }
    }

    // MARK: - Init

    init() {
        let d = UserDefaults.standard

        // Register defaults
        d.register(defaults: [
            "launchAtLogin": false,
            "refreshIntervalSec": 5,
            "showPercentInMenuBar": true,
            "showSwapInMenuBar": true,
            "notifyZombies": true,
            "notifyMemoryPressure": true,
            "memoryPressureThresholdPct": 90,
            "notifySwapGrowth": true,
            "optimizerIntervalMin": 5,
            "zombieMinAgeMin": 30,
            "chromeWarnGB": 10.0,
            "autoKillZombies": true,
            "learnSnapshotIntervalMin": 5,
            "learnExcludedApps": [String](),
        ])

        self.launchAtLogin = d.bool(forKey: "launchAtLogin")
        self.refreshIntervalSec = d.integer(forKey: "refreshIntervalSec")
        self.showPercentInMenuBar = d.bool(forKey: "showPercentInMenuBar")
        self.showSwapInMenuBar = d.bool(forKey: "showSwapInMenuBar")
        self.notifyZombies = d.bool(forKey: "notifyZombies")
        self.notifyMemoryPressure = d.bool(forKey: "notifyMemoryPressure")
        self.memoryPressureThresholdPct = d.integer(forKey: "memoryPressureThresholdPct")
        self.notifySwapGrowth = d.bool(forKey: "notifySwapGrowth")
        self.optimizerIntervalMin = d.integer(forKey: "optimizerIntervalMin")
        self.zombieMinAgeMin = d.integer(forKey: "zombieMinAgeMin")
        self.chromeWarnGB = d.double(forKey: "chromeWarnGB")
        self.autoKillZombies = d.bool(forKey: "autoKillZombies")
        self.learnSnapshotIntervalMin = d.integer(forKey: "learnSnapshotIntervalMin")
        self.learnExcludedApps = d.stringArray(forKey: "learnExcludedApps") ?? []
    }

    private func updateLoginItem() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if launchAtLogin {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                // Silently fail — user may not have granted permission
            }
        }
    }
}
