import Foundation

// MARK: - CLI Entry Point
//
// Single binary, dual-mode: when launched with a recognized subcommand, the
// app dispatches here and exits before NSApp setup. Otherwise it boots as
// the normal menu bar app.
//
// This is the GTM wedge against TUI tools — exposes the same intelligence
// the menu bar app has (zombies, idle dev servers, ports, AI memory budget)
// in a scriptable, JSON-emitting form usable from tmux/zellij/CI.

enum CLI {
    /// Recognized subcommand strings. If the first arg matches, run as CLI.
    static let subcommands: Set<String> = [
        "status", "processes", "zombies", "ports", "ai", "clean", "watch",
        "babysit",
        "help", "--help", "-h", "version", "--version",
    ]

    /// Returns true if argv looks like a CLI invocation. The app's @main
    /// entry point checks this and exits via `run` before booting NSApp.
    ///
    /// Heuristics:
    ///   1. A recognized subcommand as the first arg → CLI.
    ///   2. argv[0] basename is "devpulse" (the lowercase symlink) → CLI.
    ///   3. stdout is a TTY (running in a terminal) → CLI.
    /// Otherwise we're launched as an app bundle and should boot NSApp.
    static func shouldRun(args: [String]) -> Bool {
        if args.count >= 2, subcommands.contains(args[1]) { return true }
        if let arg0 = args.first {
            let base = (arg0 as NSString).lastPathComponent
            if base == "devpulse" { return true }
        }
        if isatty(fileno(stdout)) != 0 { return true }
        return false
    }

    static func run(args: [String]) -> Int32 {
        let cmd = args.count >= 2 ? args[1] : "help"
        let flags = Array(args.dropFirst(2))
        let json = flags.contains("--json")

        switch cmd {
        case "status":            return runStatus(json: json)
        case "processes":         return runProcesses(flags: flags, json: json)
        case "zombies":           return runZombies(flags: flags, json: json)
        case "ports":             return runPorts(json: json)
        case "ai":                return runAI(json: json, flags: flags)
        case "clean":             return runClean(flags: flags, json: json)
        case "watch":             return runWatch(flags: flags)
        case "babysit":           return runBabysit(flags: flags)
        case "version", "--version":
            print(versionString())
            return 0
        case "help", "--help", "-h":
            printHelp()
            return 0
        default:
            printHelp()
            return 1
        }
    }

    // MARK: - Commands

    static func runStatus(json: Bool) -> Int32 {
        let stats = MemoryStats.current()
        let gpu = getGPUMemoryInfo()
        let battery = getBatteryStats()
        let zombies = getZombieProcesses()
        let inactive = getInactiveDevServers()

        if json {
            var out: [String: Any] = [
                "memory": [
                    "totalGB": stats.totalGB,
                    "usedGB": stats.usedGB,
                    "freeGB": stats.freeGB,
                    "compressedGB": stats.compressedGB,
                    "swapGB": stats.swapUsedGB,
                    "usedPercent": stats.usedPercent,
                    "status": stats.status.rawValue,
                ],
                "zombies": [
                    "count": zombies.reduce(0) { $0 + $1.count },
                    "totalMB": zombies.reduce(0) { $0 + $1.totalMB },
                    "projects": zombies.map(\.project),
                ],
                "idleServers": [
                    "count": inactive.reduce(0) { $0 + $1.processes.count },
                    "totalMB": inactive.reduce(0) { $0 + $1.totalMB },
                    "projects": inactive.map(\.project),
                ],
            ]
            if let gpu {
                out["gpu"] = [
                    "allocatedMB": gpu.allocatedMB,
                    "ceilingMB": gpu.recommendedMaxMB,
                ]
            }
            if let b = battery {
                var bd: [String: Any] = [
                    "percent": b.percent,
                    "onAC": b.onAC,
                    "isCharging": b.isCharging,
                    "lowPowerMode": b.lowPowerMode,
                ]
                if let m = b.timeToEmptyMinutes { bd["timeToEmptyMinutes"] = m }
                out["battery"] = bd
            }
            printJSON(out)
            return 0
        }

        print(String(format: "memory  %.1f / %.1f GB  (%.0f%%)  [%@]",
                     stats.usedGB, stats.totalGB, stats.usedPercent, stats.status.rawValue))
        print(String(format: "swap    %.1f GB", stats.swapUsedGB))
        if let gpu {
            print(String(format: "gpu     %.1f / %.1f GB", gpu.allocatedGB, gpu.recommendedMaxGB))
        }
        if let b = battery {
            let charge = b.onAC ? (b.isCharging ? "charging" : "AC") : "battery"
            var line = String(format: "battery %d%%  [%@]", b.percent, charge)
            if let m = b.timeToEmptyMinutes, m > 0 {
                line += "  \(m / 60)h \(m % 60)m to empty"
            }
            if b.lowPowerMode { line += "  · low-power mode" }
            print(line)
        }

        let zombieMB = zombies.reduce(0) { $0 + $1.totalMB }
        let zombieCount = zombies.reduce(0) { $0 + $1.count }
        if zombieCount > 0 {
            print("")
            print("⚠  \(zombieCount) zombie procs using \(formatMB(zombieMB)) — run: devpulse zombies --kill")
        }
        let idleMB = inactive.reduce(0) { $0 + $1.totalMB }
        let idleCount = inactive.reduce(0) { $0 + $1.processes.count }
        if idleCount > 0 {
            let projects = inactive.map(\.project).joined(separator: ", ")
            print("⚠  \(idleCount) idle dev servers using \(formatMB(idleMB)) — \(projects)")
        }
        return 0
    }

    static func runProcesses(flags: [String], json: Bool) -> Int32 {
        let limit = parseIntFlag(flags, name: "-n") ?? 8
        let procs = getTopProcesses(limit: limit)

        if json {
            let out = procs.map { p -> [String: Any] in
                [
                    "name": p.name,
                    "memoryMB": p.memoryMB,
                    "childCount": p.childCount,
                    "pids": p.pids,
                ]
            }
            printJSON(out)
            return 0
        }

        for p in procs {
            let line = String(format: "%-25s %8s  (%d procs)",
                              String(p.displayName.prefix(25)),
                              formatMB(p.memoryMB),
                              p.childCount)
            print(line)
            if let bd = p.breakdownSummary {
                print("    \(bd)")
            }
        }
        return 0
    }

    static func runZombies(flags: [String], json: Bool) -> Int32 {
        let minMB = parseIntFlag(flags, name: "--min-mb") ?? 0
        let zombies = getZombieProcesses().filter { $0.totalMB >= minMB }
        let shouldKill = flags.contains("--kill")

        if json {
            let out = zombies.map { z -> [String: Any] in
                [
                    "project": z.project,
                    "kind": z.kind.rawValue,
                    "count": z.count,
                    "totalMB": z.totalMB,
                    "pids": z.pids,
                ]
            }
            printJSON(out)
            return 0
        }

        if zombies.isEmpty {
            print("no zombies detected")
            return 0
        }

        for z in zombies {
            print(String(format: "%-20s %-12s %5d procs  %s",
                         String(z.project.prefix(20)),
                         z.kind.rawValue,
                         z.count,
                         formatMB(z.totalMB)))
        }
        let totalMB = zombies.reduce(0) { $0 + $1.totalMB }
        let totalCount = zombies.reduce(0) { $0 + $1.count }
        print("")
        print("total: \(totalCount) procs, \(formatMB(totalMB))")

        if shouldKill {
            let allPids = zombies.flatMap(\.pids)
            for pid in allPids { kill(pid, SIGTERM) }
            Thread.sleep(forTimeInterval: 2)
            for pid in allPids { kill(pid, SIGKILL) }
            print("killed \(allPids.count) procs (\(formatMB(totalMB)) reclaimed)")
        }
        return 0
    }

    static func runPorts(json: Bool) -> Int32 {
        let scan = scanListeningPorts()

        if json {
            let out: [String: Any] = [
                "ports": scan.ports.map { p in
                    [
                        "port": p.port,
                        "pid": p.pid,
                        "process": p.processName,
                        "project": p.project as Any,
                        "isDevPort": p.isDevPort,
                    ]
                },
                "conflicts": scan.conflicts.map { c in
                    [
                        "port": c.port,
                        "holders": c.holders.map(\.displayName),
                    ]
                },
                "systemConflicts": scan.systemConflicts.map { p in
                    ["port": p.port, "process": p.processName]
                },
            ]
            printJSON(out)
            return 0
        }

        if !scan.conflicts.isEmpty {
            print("conflicts:")
            for c in scan.conflicts {
                print("  :\(c.port)  \(c.holders.map(\.displayName).joined(separator: " vs "))")
            }
            print("")
        }
        if !scan.systemConflicts.isEmpty {
            print("system service on dev port:")
            for p in scan.systemConflicts {
                print("  :\(p.port)  \(p.processName)")
            }
            print("")
        }
        for p in scan.ports.filter(\.isDevPort) {
            let proj = p.project.map { " (\($0))" } ?? ""
            print(String(format: "  :%-5d  %@%@", p.port, p.processName, proj))
        }
        return 0
    }

    static func runAI(json: Bool, flags: [String] = []) -> Int32 {
        let monitor = OllamaMonitor()
        let status = monitor.getStatus()
        let gpu = getGPUMemoryInfo()
        let stats = MemoryStats.current()
        let budget = AIMemoryBudget.calculate(stats: stats, gpu: gpu, ollama: status)

        // Pre-flight predicate: agents pass --before-load <MB> and branch on
        // exit code. Exit 0 = fits, 1 = won't fit at all, 2 = fits after
        // unloading idle models. With --auto-clean, perform the cleanup
        // (unload idle Ollama models, kill zombies) and re-evaluate; the
        // final exit code reflects the post-cleanup state.
        if let beforeLoadMB = parseIntFlag(flags, name: "--before-load") {
            let autoClean = flags.contains("--auto-clean")
            let prediction = budget.predictLoadImpact(modelSizeMB: beforeLoadMB)
            let (code, verdict) = beforeLoadVerdict(prediction)

            // Auto-clean path: only useful if cleanup could help — we need
            // either reclaimable idle models or zombies to act on.
            if autoClean, code != 0 {
                let actions = autoCleanForLoad(
                    monitor: monitor,
                    ollama: status,
                    json: json
                )
                // Re-evaluate after cleanup.
                let stats2 = MemoryStats.current()
                let gpu2 = getGPUMemoryInfo()
                let ollama2 = monitor.getStatus()
                let budget2 = AIMemoryBudget.calculate(stats: stats2, gpu: gpu2, ollama: ollama2)
                let prediction2 = budget2.predictLoadImpact(modelSizeMB: beforeLoadMB)
                let (code2, verdict2) = beforeLoadVerdict(prediction2)

                if json {
                    var out: [String: Any] = [
                        "modelSizeMB": beforeLoadMB,
                        "autoClean": true,
                        "before": ["verdict": verdict, "exitCode": code, "description": prediction.description],
                        "actions": actions,
                        "after": [
                            "verdict": verdict2,
                            "exitCode": code2,
                            "description": prediction2.description,
                            "availableForAIMB": budget2.availableForAIMB,
                        ],
                    ]
                    out["exitCode"] = code2
                    out["verdict"] = verdict2
                    printJSON(out)
                } else {
                    print("before: \(prediction.description)")
                    for a in actions { print("  - \(a)") }
                    print("after:  \(prediction2.description)")
                }
                return code2
            }

            if json {
                var out: [String: Any] = [
                    "modelSizeMB": beforeLoadMB,
                    "verdict": verdict,
                    "exitCode": code,
                    "description": prediction.description,
                    "availableForAIMB": budget.availableForAIMB,
                    "reclaimableFromIdleMB": budget.reclaimableFromIdleMB,
                ]
                if let s = status, !s.idleModels.isEmpty {
                    out["unloadCandidates"] = s.idleModels.map { ["name": $0.name, "sizeMB": $0.sizeMB] }
                }
                printJSON(out)
            } else {
                print(prediction.description)
                if code == 2, let s = status {
                    let candidates = s.idleModels.map { "\($0.name) (\($0.sizeFormatted))" }.joined(separator: ", ")
                    if !candidates.isEmpty {
                        print("unload: \(candidates)")
                    }
                }
            }
            return code
        }

        if json {
            var out: [String: Any] = [
                "budget": [
                    "totalRAMMB": budget.totalRAMMB,
                    "gpuCeilingMB": budget.gpuCeilingMB,
                    "gpuAllocatedMB": budget.gpuAllocatedMB,
                    "ollamaModelsMB": budget.ollamaModelsMB,
                    "availableForAIMB": budget.availableForAIMB,
                    "reclaimableFromIdleMB": budget.reclaimableFromIdleMB,
                ],
            ]
            if let s = status {
                out["ollama"] = [
                    "running": s.isRunning,
                    "totalVRAMMB": s.totalVRAMMB,
                    "models": s.loadedModels.map { m in
                        [
                            "name": m.name,
                            "sizeMB": m.sizeMB,
                            "isIdle": m.isIdle,
                        ]
                    },
                ]
            }
            printJSON(out)
            return 0
        }

        if let s = status, s.isRunning {
            print("ollama: \(s.loadedModels.count) models, \(s.totalVRAMFormatted) VRAM")
            for m in s.loadedModels {
                let idleMark = m.isIdle ? " (idle)" : ""
                print("  \(m.name)  \(m.sizeFormatted)\(idleMark)")
            }
            print("")
        } else {
            print("ollama: not running")
            print("")
        }
        print("ai memory budget:")
        print("  available  \(formatMB(budget.availableForAIMB))")
        print("  reclaimable from idle  \(formatMB(budget.reclaimableFromIdleMB))")
        print("  gpu allocated  \(formatMB(budget.gpuAllocatedMB)) / \(formatMB(budget.gpuCeilingMB))")
        return 0
    }

    static func runClean(flags: [String], json: Bool) -> Int32 {
        let dryRun = flags.contains("--dry-run")

        if dryRun {
            let scan = scanAllCleanups()
            let artifacts = scanDevArtifacts()
            if json {
                let out: [String: Any] = [
                    "dryRun": true,
                    "derivedDataStaleMB": scan.derivedData.staleMB,
                    "spotlightIssueCount": scan.spotlightIssues.issueCount,
                    "dockerCacheMB": scan.dockerCache.totalMB,
                    "totalReclaimableMB": scan.totalReclaimableMB,
                    "devArtifactStaleMB": artifacts.staleMB,
                ]
                printJSON(out)
                return 0
            }
            print("would reclaim:")
            print("  stale DerivedData       \(formatMB(scan.derivedData.staleMB))")
            print("  spotlight fixes         \(scan.spotlightIssues.issueCount) dirs")
            print("  docker reclaimable      \(formatMB(scan.dockerCache.totalMB))")
            print("  stale dev artifacts     \(formatMB(artifacts.staleMB))")
            print("  ─────────")
            print("  total                   \(formatMB(scan.totalReclaimableMB + artifacts.staleMB))")
            print("")
            print("rerun without --dry-run to apply")
            return 0
        }

        let result = runQuickClean()
        if json {
            let out: [String: Any] = [
                "freedMB": result.totalFreedMB,
                "actions": result.results.map { ["action": $0.action, "freedMB": $0.freedMB, "detail": $0.detail] },
            ]
            printJSON(out)
            return 0
        }
        for r in result.results {
            print("\(r.action): \(r.detail) (\(formatMB(r.freedMB)))")
        }
        print("")
        print("freed: \(result.freedFormatted)")
        return 0
    }

    // MARK: - Watch (streaming NDJSON)

    static func runWatch(flags: [String]) -> Int32 {
        let interval = parseIntFlag(flags, name: "--interval") ?? 15
        let monitor = OllamaMonitor()

        // Line-buffered stdout so each tick reaches the consumer immediately.
        setlinebuf(stdout)

        // Clean exit on SIGINT/SIGTERM so callers can pipe into agents.
        signal(SIGINT) { _ in exit(0) }
        signal(SIGTERM) { _ in exit(0) }

        while true {
            let stats = MemoryStats.current()
            let gpu = getGPUMemoryInfo()
            let zombies = getZombieProcesses()
            let inactive = getInactiveDevServers()
            let ollama = monitor.getStatus()
            let battery = getBatteryStats()
            let budget = AIMemoryBudget.calculate(stats: stats, gpu: gpu, ollama: ollama)

            var batteryDict: [String: Any]? = nil
            if let b = battery {
                var d: [String: Any] = [
                    "percent": b.percent,
                    "onAC": b.onAC,
                    "isCharging": b.isCharging,
                    "lowPowerMode": b.lowPowerMode,
                ]
                if let m = b.timeToEmptyMinutes { d["timeToEmptyMinutes"] = m }
                batteryDict = d
            }

            let tick: [String: Any] = [
                "ts": ISO8601DateFormatter().string(from: Date()),
                "memory": [
                    "usedGB": stats.usedGB,
                    "totalGB": stats.totalGB,
                    "swapGB": stats.swapUsedGB,
                    "usedPercent": stats.usedPercent,
                    "status": stats.status.rawValue,
                ],
                "gpu": gpu.map { ["allocatedMB": $0.allocatedMB, "ceilingMB": $0.recommendedMaxMB] } as Any,
                "battery": batteryDict as Any,
                "zombies": [
                    "count": zombies.reduce(0) { $0 + $1.count },
                    "totalMB": zombies.reduce(0) { $0 + $1.totalMB },
                ],
                "idleServers": [
                    "count": inactive.reduce(0) { $0 + $1.processes.count },
                    "totalMB": inactive.reduce(0) { $0 + $1.totalMB },
                ],
                "ai": [
                    "availableForAIMB": budget.availableForAIMB,
                    "reclaimableFromIdleMB": budget.reclaimableFromIdleMB,
                    "ollamaModelsMB": budget.ollamaModelsMB,
                ],
            ]

            // Single-line JSON (NDJSON), not pretty-printed.
            if let data = try? JSONSerialization.data(withJSONObject: tick, options: [.sortedKeys]),
               let line = String(data: data, encoding: .utf8) {
                print(line)
            }

            Thread.sleep(forTimeInterval: TimeInterval(interval))
        }
    }

    // MARK: - Babysit (long-run watchdog)
    //
    // Built for the literal "70B model on an 11-hour transatlantic flight"
    // pattern: long-running local AI workload, no internet, intermittent
    // power. Babysit watches free VRAM + battery, auto-cleans when pressure
    // builds, and emits NDJSON events the caller can checkpoint on.

    static func runBabysit(flags: [String]) -> Int32 {
        let interval = parseIntFlag(flags, name: "--interval") ?? 30
        let durationMin = parseIntFlag(flags, name: "--duration")
        // Free VRAM threshold (MB). Below this we trigger auto-clean.
        let targetFreeMB = parseIntFlag(flags, name: "--target-free-mb") ?? 2048
        let json = flags.contains("--json")

        setlinebuf(stdout)
        signal(SIGINT) { _ in exit(0) }
        signal(SIGTERM) { _ in exit(0) }

        let monitor = OllamaMonitor()
        let started = Date()
        var ticks = 0
        var cleanupRuns = 0
        var totalReclaimedMB = 0

        // Session log: always write NDJSON to the standard path so the
        // menu bar app's Babysit Dashboard can replay sessions, regardless
        // of whether --json was passed for stdout.
        let sessionLogURL = BabysitSessionStore.newSessionLogURL(startedAt: started)
        let sessionLogHandle = BabysitSessionStore.openSessionLog(at: sessionLogURL)

        func emit(event: String, payload: [String: Any]) {
            var p = payload
            p["ts"] = ISO8601DateFormatter().string(from: Date())
            p["event"] = event

            // Always write to the session log (one NDJSON line per event).
            if let data = try? JSONSerialization.data(withJSONObject: p, options: [.sortedKeys]),
               let line = String(data: data, encoding: .utf8),
               let lineData = (line + "\n").data(using: .utf8) {
                sessionLogHandle?.write(lineData)
            }

            // Stdout: JSON or human-readable depending on flag.
            if json {
                if let data = try? JSONSerialization.data(withJSONObject: p, options: [.sortedKeys]),
                   let line = String(data: data, encoding: .utf8) {
                    print(line)
                }
            } else {
                let stamp = ISO8601DateFormatter().string(from: Date())
                let detail = payload.map { "\($0)=\($1)" }.sorted().joined(separator: " ")
                print("[\(stamp)] \(event)  \(detail)")
            }
        }

        emit(event: "started", payload: [
            "intervalSec": interval,
            "targetFreeMB": targetFreeMB,
            "durationMin": durationMin as Any,
        ])

        while true {
            ticks += 1
            let stats = MemoryStats.current()
            let gpu = getGPUMemoryInfo()
            let ollama = monitor.getStatus()
            let battery = getBatteryStats()
            let budget = AIMemoryBudget.calculate(stats: stats, gpu: gpu, ollama: ollama)

            var pressureReasons: [String] = []
            if budget.availableForAIMB < targetFreeMB {
                pressureReasons.append("free<\(targetFreeMB)MB")
            }
            if let b = battery, !b.onAC, b.percent <= 20 {
                pressureReasons.append("battery<=20%")
            }
            if stats.swapUsedGB > 10 {
                pressureReasons.append("swap>10GB")
            }

            emit(event: "tick", payload: [
                "tickNum": ticks,
                "availableForAIMB": budget.availableForAIMB,
                "swapGB": stats.swapUsedGB,
                "memUsedPercent": Int(stats.usedPercent),
                "batteryPercent": battery?.percent as Any,
                "onAC": battery?.onAC as Any,
                "pressure": pressureReasons.joined(separator: ","),
            ])

            // Trigger auto-clean only when there's something to reclaim and
            // we're under pressure. Avoid noise on healthy ticks.
            let canReclaim = (ollama?.hasIdleModels ?? false) || !getZombieProcesses().isEmpty
            if !pressureReasons.isEmpty && canReclaim {
                let actions = autoCleanForLoad(monitor: monitor, ollama: ollama, json: json)
                cleanupRuns += 1

                let after = MemoryStats.current()
                let afterGPU = getGPUMemoryInfo()
                let afterBudget = AIMemoryBudget.calculate(stats: after, gpu: afterGPU, ollama: monitor.getStatus())
                let reclaimed = afterBudget.availableForAIMB - budget.availableForAIMB
                if reclaimed > 0 { totalReclaimedMB += reclaimed }

                emit(event: "cleanup", payload: [
                    "reasons": pressureReasons.joined(separator: ","),
                    "actions": actions,
                    "reclaimedMB": max(reclaimed, 0),
                    "availableForAIMB": afterBudget.availableForAIMB,
                ])
            }

            // Duration cap.
            if let mins = durationMin, Date().timeIntervalSince(started) >= TimeInterval(mins * 60) {
                emit(event: "done", payload: [
                    "ticks": ticks,
                    "cleanupRuns": cleanupRuns,
                    "totalReclaimedMB": totalReclaimedMB,
                    "elapsedMin": Int(Date().timeIntervalSince(started) / 60),
                ])
                return 0
            }

            Thread.sleep(forTimeInterval: TimeInterval(interval))
        }
    }

    /// Map a load prediction to a CLI exit code + short verdict tag.
    /// 0 = fits, 1 = won't fit, 2 = fits after unloading idle models, 3 = tight.
    static func beforeLoadVerdict(_ p: LoadPrediction) -> (code: Int32, verdict: String) {
        switch p {
        case .comfortable:     return (0, "fits")
        case .tight:           return (3, "tight")
        case .fitsAfterUnload: return (2, "fits-after-unload")
        case .willNotFit:      return (1, "wont-fit")
        }
    }

    /// Perform the safe cleanup actions before loading a large model:
    /// unload idle Ollama models and kill orphaned dev procs. Returns
    /// human-readable action strings for reporting back to the caller.
    static func autoCleanForLoad(
        monitor: OllamaMonitor,
        ollama: OllamaStatus?,
        json: Bool
    ) -> [String] {
        var actions: [String] = []

        // 1. Unload idle Ollama models (frees VRAM directly).
        if let s = ollama {
            for model in s.idleModels {
                if monitor.unloadModel(model.name) {
                    actions.append("unloaded idle ollama model: \(model.name) (\(model.sizeFormatted))")
                }
            }
        }

        // 2. Kill zombie procs (orphaned dev tools, stale LSPs, watchers).
        let zombies = getZombieProcesses()
        if !zombies.isEmpty {
            let pids = zombies.flatMap(\.pids)
            let totalMB = zombies.reduce(0) { $0 + $1.totalMB }
            for pid in pids { kill(pid, SIGTERM) }
            Thread.sleep(forTimeInterval: 1)
            for pid in pids { kill(pid, SIGKILL) }
            actions.append("killed \(pids.count) zombie procs (\(formatMB(totalMB)) reclaimed)")
        }

        // Give the kernel a moment to reflect freed memory before re-eval.
        if !actions.isEmpty {
            Thread.sleep(forTimeInterval: 1)
        }

        return actions
    }

    // MARK: - Helpers

    static func printHelp() {
        print("""
        devpulse — system intelligence for developers

        usage: devpulse <command> [flags]

        commands:
          status                       overall: memory, swap, GPU, top issues
          processes [-n N]             top memory consumers grouped by app
          zombies [--kill] [--min-mb N]  orphaned procs / stale LSPs / watchers
          ports                        listening dev ports + conflicts
          ai [--before-load <MB>]      Ollama + AI memory budget; pre-flight check
                                       add --auto-clean to unload idle models and
                                       kill zombies, then re-evaluate
          clean [--dry-run]            reclaim DerivedData / docker / dev caches
          watch [--interval SECS]      stream NDJSON ticks (default 15s)
          babysit [--target-free-mb N] [--duration MIN] [--json]
                                       long-run watchdog: auto-cleans when
                                       VRAM/battery/swap cross thresholds
          version                      print version

        global flags:
          --json             emit machine-readable output

        exit codes (--before-load):
          0 fits  •  1 won't fit  •  2 fits after unloading idle  •  3 tight

        examples:
          devpulse status --json | jq .memory.usedGB
          devpulse zombies --json --min-mb 100
          devpulse ai --before-load 8000 || devpulse zombies --kill
          devpulse ai --before-load 42000 --auto-clean --json
          devpulse watch --interval 30 | your-agent
          devpulse babysit --duration 660 --json > flight.log
        """)
    }

    static func versionString() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static func parseIntFlag(_ flags: [String], name: String) -> Int? {
        guard let idx = flags.firstIndex(of: name), idx + 1 < flags.count else { return nil }
        return Int(flags[idx + 1])
    }

    static func formatMB(_ mb: Int) -> String {
        mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
    }

    static func printJSON(_ obj: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return }
        print(str)
    }
}
