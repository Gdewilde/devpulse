import Foundation

// MARK: - Ollama Live Monitor
// Queries the local Ollama API to detect running models, memory usage,
// idle time, and provides unload/cleanup capabilities.

struct OllamaStatus {
    let isRunning: Bool
    let loadedModels: [LoadedModel]
    let totalVRAMMB: Int
    let idleModels: [LoadedModel]
    let installedModels: [InstalledModel]

    var totalVRAMFormatted: String {
        totalVRAMMB >= 1024
            ? String(format: "%.1f GB", Double(totalVRAMMB) / 1024)
            : "\(totalVRAMMB) MB"
    }

    var hasIdleModels: Bool { !idleModels.isEmpty }

    var idleVRAMMB: Int { idleModels.reduce(0) { $0 + $1.sizeMB } }

    var idleVRAMFormatted: String {
        let mb = idleVRAMMB
        return mb >= 1024
            ? String(format: "%.1f GB", Double(mb) / 1024)
            : "\(mb) MB"
    }

    /// Total disk space used by installed models.
    var installedDiskMB: Int { installedModels.reduce(0) { $0 + $1.sizeMB } }

    var installedDiskFormatted: String {
        let mb = installedDiskMB
        return mb >= 1024
            ? String(format: "%.1f GB", Double(mb) / 1024)
            : "\(mb) MB"
    }

    /// Installed models that are not currently loaded into VRAM.
    var unloadedInstalledModels: [InstalledModel] {
        let loadedNames = Set(loadedModels.map(\.name))
        return installedModels.filter { !loadedNames.contains($0.name) }
    }

    /// Installed models whose on-disk file hasn't been touched in 30+ days.
    var staleInstalledModels: [InstalledModel] {
        installedModels.filter { $0.daysSinceModified >= 30 }
    }

    var staleDiskMB: Int { staleInstalledModels.reduce(0) { $0 + $1.sizeMB } }
}

/// A model present on disk (from /api/tags), whether or not it's currently loaded.
struct InstalledModel {
    let name: String           // e.g. "llama3.1:8b"
    let sizeMB: Int            // disk size
    let family: String
    let parameterSize: String
    let quantization: String
    let modifiedAt: Date?      // last-modified time of the manifest

    var sizeFormatted: String {
        sizeMB >= 1024
            ? String(format: "%.1f GB", Double(sizeMB) / 1024)
            : "\(sizeMB) MB"
    }

    /// Days since the model file was last modified (proxy for last-used).
    /// Ollama doesn't expose true last-used; modifiedAt is set on pull and
    /// is the best stand-in we have without scanning model directories.
    var daysSinceModified: Int {
        guard let modifiedAt = modifiedAt else { return 0 }
        return Int(Date().timeIntervalSince(modifiedAt) / 86400)
    }
}

struct LoadedModel {
    let name: String           // e.g. "llama3.1:8b"
    let sizeMB: Int            // VRAM consumed
    let family: String         // e.g. "llama"
    let parameterSize: String  // e.g. "8B"
    let quantization: String   // e.g. "Q4_K_M"
    let expiresAt: Date?       // when Ollama will auto-unload
    let loadedSince: Date?     // approximate load time

    var isIdle: Bool {
        // If expires_at is in the future and close to the default 5-min timeout,
        // the model hasn't been queried recently. A model that was just queried
        // gets its expiry pushed forward.
        guard let expires = expiresAt else { return false }
        let remaining = expires.timeIntervalSinceNow
        // If more than 4 minutes remain, it was recently queried
        // If less than 2 minutes, it's winding down — consider idle
        return remaining < 120
    }

    var idleDuration: String? {
        guard let expires = expiresAt else { return nil }
        let remaining = expires.timeIntervalSinceNow
        if remaining <= 0 { return "expiring" }
        if remaining < 60 { return "\(Int(remaining))s left" }
        return "\(Int(remaining / 60))m left"
    }

    var sizeFormatted: String {
        sizeMB >= 1024
            ? String(format: "%.1f GB", Double(sizeMB) / 1024)
            : "\(sizeMB) MB"
    }

    var displayName: String {
        // Shorten "llama3.1:8b-instruct-q4_K_M" to "Llama 3.1 8B"
        let parts = name.split(separator: ":")
        let base = String(parts.first ?? Substring(name))
        return base
    }
}

// MARK: - Local AI runtime detection

/// What local AI runtimes are installed on this machine.
/// Detection is presentation-neutral: we list them so users can pick.
struct LocalAIRuntimes {
    let ollamaInstalled: Bool
    let lmStudioInstalled: Bool
    let llamaCppInstalled: Bool
    let mlxInstalled: Bool

    var anyInstalled: Bool {
        ollamaInstalled || lmStudioInstalled || llamaCppInstalled || mlxInstalled
    }

    static func detect() -> LocalAIRuntimes {
        let fm = FileManager.default
        let ollama = fm.fileExists(atPath: "/Applications/Ollama.app") ||
                     fm.fileExists(atPath: "/usr/local/bin/ollama") ||
                     fm.fileExists(atPath: "/opt/homebrew/bin/ollama")
        let lmStudio = fm.fileExists(atPath: "/Applications/LM Studio.app") ||
                       fm.fileExists(atPath: NSHomeDirectory() + "/Applications/LM Studio.app")
        let llamaCpp = fm.fileExists(atPath: "/usr/local/bin/llama-server") ||
                       fm.fileExists(atPath: "/opt/homebrew/bin/llama-server") ||
                       fm.fileExists(atPath: "/usr/local/bin/llama-cli") ||
                       fm.fileExists(atPath: "/opt/homebrew/bin/llama-cli")
        // MLX is a Python package; detecting it without launching python is unreliable.
        // Skip for now; user can install via pip and we won't claim presence.
        let mlx = false
        return LocalAIRuntimes(
            ollamaInstalled: ollama,
            lmStudioInstalled: lmStudio,
            llamaCppInstalled: llamaCpp,
            mlxInstalled: mlx
        )
    }
}

// MARK: - Pull progress

/// State of an in-flight `ollama pull` operation.
struct OllamaPullState {
    let modelName: String
    let status: String         // e.g. "pulling manifest", "downloading", "verifying"
    let totalBytes: Int64
    let completedBytes: Int64
    let startedAt: Date
    let isComplete: Bool
    let error: String?

    var percent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(completedBytes) / Double(totalBytes)
    }

    var percentText: String {
        if totalBytes == 0 { return status }
        return String(format: "%.0f%%", percent * 100)
    }

    var bytesText: String {
        guard totalBytes > 0 else { return "" }
        return "\(formatBytes(completedBytes)) / \(formatBytes(totalBytes))"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }
}

/// Streams `POST /api/pull` and emits progress updates on the main queue.
/// One pull at a time. Cancellable by calling `cancel()`.
final class OllamaPullManager: NSObject, URLSessionDataDelegate {
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var buffer = Data()
    private let modelName: String
    private let baseURL: String
    private let onUpdate: (OllamaPullState) -> Void
    private var lastStatus: String = "starting"
    private var lastTotal: Int64 = 0
    private var lastCompleted: Int64 = 0
    private let startedAt = Date()
    private var finished = false

    init(modelName: String, baseURL: String, onUpdate: @escaping (OllamaPullState) -> Void) {
        self.modelName = modelName
        self.baseURL = baseURL
        self.onUpdate = onUpdate
    }

    func start() {
        guard let url = URL(string: "\(baseURL)/api/pull") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 0  // streaming — let it run

        let body: [String: Any] = ["model": modelName, "stream": true]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 0
        config.timeoutIntervalForResource = 0
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session

        emit(status: "starting download", isComplete: false, error: nil)

        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
        if !finished {
            finished = true
            emit(status: "cancelled", isComplete: true, error: "cancelled")
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        // Split on newlines (NDJSON)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: 0..<nl)
            buffer.removeSubrange(0...nl)
            handleLine(lineData)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Drain final buffered line if any
        if !buffer.isEmpty {
            handleLine(buffer)
            buffer.removeAll()
        }
        if finished { return }
        finished = true
        if let error = error, (error as NSError).code != NSURLErrorCancelled {
            emit(status: "error", isComplete: true, error: error.localizedDescription)
        } else {
            emit(status: "success", isComplete: true, error: nil)
        }
    }

    private func handleLine(_ data: Data) {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let status = obj["status"] as? String { lastStatus = status }
        if let total = obj["total"] as? Int64 { lastTotal = total }
        if let completed = obj["completed"] as? Int64 { lastCompleted = completed }
        // Some responses use Int instead of Int64
        if lastTotal == 0, let total = obj["total"] as? Int { lastTotal = Int64(total) }
        if lastCompleted == 0, let completed = obj["completed"] as? Int { lastCompleted = Int64(completed) }

        let isDone = (lastStatus == "success")
        if isDone { finished = true }

        if let errStr = obj["error"] as? String {
            finished = true
            emit(status: "error", isComplete: true, error: errStr)
            return
        }

        emit(status: lastStatus, isComplete: isDone, error: nil)
    }

    private func emit(status: String, isComplete: Bool, error: String?) {
        let state = OllamaPullState(
            modelName: modelName,
            status: status,
            totalBytes: lastTotal,
            completedBytes: lastCompleted,
            startedAt: startedAt,
            isComplete: isComplete,
            error: error
        )
        DispatchQueue.main.async { self.onUpdate(state) }
    }
}

// MARK: - Ollama API Client

/// Queries the local Ollama HTTP API (default port 11434).
class OllamaMonitor {
    private let baseURL: String
    private let session: URLSession
    private let timeout: TimeInterval = 2.0 // fast timeout — local only

    init(port: Int = 11434) {
        self.baseURL = "http://127.0.0.1:\(port)"

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
    }

    /// Check Ollama status and loaded models. Returns nil if Ollama isn't running.
    func getStatus() -> OllamaStatus? {
        guard isRunning() else {
            return OllamaStatus(isRunning: false, loadedModels: [], totalVRAMMB: 0,
                                idleModels: [], installedModels: [])
        }

        let models = getLoadedModels()
        let installed = getInstalledModels()
        let totalVRAM = models.reduce(0) { $0 + $1.sizeMB }
        let idle = models.filter(\.isIdle)

        return OllamaStatus(
            isRunning: true,
            loadedModels: models,
            totalVRAMMB: totalVRAM,
            idleModels: idle,
            installedModels: installed
        )
    }

    /// Check if Ollama is running by hitting the root endpoint.
    func isRunning() -> Bool {
        guard let url = URL(string: baseURL) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout

        let sem = DispatchSemaphore(value: 0)
        var alive = false

        session.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                alive = true
            }
            sem.signal()
        }.resume()

        _ = sem.wait(timeout: .now() + 3)
        return alive
    }

    /// Get currently loaded models via /api/ps
    func getLoadedModels() -> [LoadedModel] {
        guard let url = URL(string: "\(baseURL)/api/ps") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        let sem = DispatchSemaphore(value: 0)
        var result: [LoadedModel] = []

        session.dataTask(with: request) { data, _, _ in
            defer { sem.signal() }
            guard let data = data else { return }
            result = Self.parseModels(data)
        }.resume()

        _ = sem.wait(timeout: .now() + 3)
        return result
    }

    /// Get all models present on disk via /api/tags (whether loaded or not).
    func getInstalledModels() -> [InstalledModel] {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        let sem = DispatchSemaphore(value: 0)
        var result: [InstalledModel] = []

        session.dataTask(with: request) { data, _, _ in
            defer { sem.signal() }
            guard let data = data else { return }
            result = Self.parseInstalledModels(data)
        }.resume()

        _ = sem.wait(timeout: .now() + 3)
        return result
    }

    /// Unload a specific model by loading a dummy and immediately cancelling,
    /// or by using the keep_alive=0 trick.
    func unloadModel(_ modelName: String) -> Bool {
        guard let url = URL(string: "\(baseURL)/api/generate") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5.0

        let body: [String: Any] = [
            "model": modelName,
            "keep_alive": 0
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let sem = DispatchSemaphore(value: 0)
        var success = false

        session.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                success = true
            }
            sem.signal()
        }.resume()

        _ = sem.wait(timeout: .now() + 5)
        return success
    }

    /// Load a model into VRAM by sending an empty prompt with keep_alive.
    /// Returns true on success.
    func loadModel(_ modelName: String) -> Bool {
        guard let url = URL(string: "\(baseURL)/api/generate") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60.0  // model load can take a while

        let body: [String: Any] = [
            "model": modelName,
            "prompt": "",
            "stream": false,
            "keep_alive": "5m"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let sem = DispatchSemaphore(value: 0)
        var success = false

        // Use a session with longer timeout for this specific call
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60.0
        config.timeoutIntervalForResource = 60.0
        let loadSession = URLSession(configuration: config)

        loadSession.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                success = true
            }
            sem.signal()
        }.resume()

        _ = sem.wait(timeout: .now() + 65)
        return success
    }

    /// Delete an installed model from disk via DELETE /api/delete.
    /// Returns true on success.
    func deleteModel(_ modelName: String) -> Bool {
        guard let url = URL(string: "\(baseURL)/api/delete") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0

        let body: [String: Any] = ["model": modelName]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let sem = DispatchSemaphore(value: 0)
        var success = false

        session.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                success = true
            }
            sem.signal()
        }.resume()

        _ = sem.wait(timeout: .now() + 12)
        return success
    }

    /// Unload all loaded models.
    func unloadAllModels() -> Int {
        let models = getLoadedModels()
        var count = 0
        for model in models {
            if unloadModel(model.name) { count += 1 }
        }
        return count
    }

    // MARK: - Parsing

    static func parseInstalledModels(_ data: Data) -> [InstalledModel] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return []
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatterNoFrac = ISO8601DateFormatter()
        isoFormatterNoFrac.formatOptions = [.withInternetDateTime]

        return models.compactMap { m -> InstalledModel? in
            guard let name = m["name"] as? String else { return nil }
            let sizeBytes = m["size"] as? Int64 ?? 0
            let sizeMB = Int(sizeBytes / 1_048_576)

            let details = m["details"] as? [String: Any] ?? [:]
            let family = details["family"] as? String ?? ""
            let paramSize = details["parameter_size"] as? String ?? ""
            let quant = details["quantization_level"] as? String ?? ""

            let modifiedStr = m["modified_at"] as? String ?? ""
            let modifiedAt = isoFormatter.date(from: modifiedStr) ?? isoFormatterNoFrac.date(from: modifiedStr)

            return InstalledModel(
                name: name,
                sizeMB: sizeMB,
                family: family,
                parameterSize: paramSize,
                quantization: quant,
                modifiedAt: modifiedAt
            )
        }
    }

    static func parseModels(_ data: Data) -> [LoadedModel] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return []
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let isoFormatterNoFrac = ISO8601DateFormatter()
        isoFormatterNoFrac.formatOptions = [.withInternetDateTime]

        return models.compactMap { m -> LoadedModel? in
            guard let name = m["name"] as? String else { return nil }

            // Size in bytes
            let sizeBytes = m["size"] as? Int64 ?? m["size_vram"] as? Int64 ?? 0
            let sizeMB = Int(sizeBytes / 1_048_576)

            // Model details
            let details = m["details"] as? [String: Any] ?? [:]
            let family = details["family"] as? String ?? ""
            let paramSize = details["parameter_size"] as? String ?? ""
            let quant = details["quantization_level"] as? String ?? ""

            // Expiry
            let expiresStr = m["expires_at"] as? String ?? ""
            let expiresAt = isoFormatter.date(from: expiresStr) ?? isoFormatterNoFrac.date(from: expiresStr)

            return LoadedModel(
                name: name,
                sizeMB: sizeMB,
                family: family,
                parameterSize: paramSize,
                quantization: quant,
                expiresAt: expiresAt,
                loadedSince: nil
            )
        }
    }
}

// MARK: - AI Memory Budget

/// Calculates how memory is distributed across dev tools vs AI workloads.
struct AIMemoryBudget {
    let totalRAMMB: Int
    let gpuCeilingMB: Int          // Metal's recommendedMaxWorkingSetSize (~75% of RAM)
    let gpuAllocatedMB: Int        // Currently allocated GPU memory
    let ollamaModelsMB: Int        // Memory consumed by loaded Ollama models
    let devStackMB: Int            // Docker + IDE + browser etc (non-Ollama used memory)
    let availableForAIMB: Int      // What's actually free for new model loads
    let reclaimableFromIdleMB: Int // Could free by unloading idle models

    var totalRAMGB: Double { Double(totalRAMMB) / 1024 }
    var gpuCeilingGB: Double { Double(gpuCeilingMB) / 1024 }

    var availableForAIFormatted: String {
        let mb = availableForAIMB
        return mb >= 1024
            ? String(format: "%.1f GB", Double(mb) / 1024)
            : "\(mb) MB"
    }

    /// Max context tokens estimable for a given model's per-token KV cache cost.
    /// Rough estimate: ~0.5 MB per 1K tokens for 7B models, scales with model size.
    func maxContextTokens(modelParamB: Int) -> Int {
        let kvCostPerKTokenMB: Double
        switch modelParamB {
        case ...3:   kvCostPerKTokenMB = 0.25
        case ...8:   kvCostPerKTokenMB = 0.5
        case ...14:  kvCostPerKTokenMB = 0.75
        case ...32:  kvCostPerKTokenMB = 1.5
        case ...70:  kvCostPerKTokenMB = 3.0
        default:     kvCostPerKTokenMB = 5.0
        }

        let availableMB = Double(availableForAIMB + reclaimableFromIdleMB)
        guard kvCostPerKTokenMB > 0, availableMB > 0 else { return 0 }
        let kTokens = availableMB / kvCostPerKTokenMB
        return Int(kTokens * 1024)
    }

    /// Build from current system state.
    static func calculate(
        stats: MemoryStats,
        gpu: GPUMemoryInfo?,
        ollama: OllamaStatus?
    ) -> AIMemoryBudget {
        let totalMB = Int(stats.totalGB * 1024)
        let gpuCeiling = gpu?.recommendedMaxMB ?? Int(Double(totalMB) * 0.75)
        let gpuAllocated = gpu?.allocatedMB ?? 0
        let ollamaMB = ollama?.totalVRAMMB ?? 0
        let usedMB = Int(stats.usedGB * 1024)
        let devStack = max(usedMB - ollamaMB, 0)
        let available = max(gpuCeiling - gpuAllocated, 0)
        let reclaimable = ollama?.idleVRAMMB ?? 0

        return AIMemoryBudget(
            totalRAMMB: totalMB,
            gpuCeilingMB: gpuCeiling,
            gpuAllocatedMB: gpuAllocated,
            ollamaModelsMB: ollamaMB,
            devStackMB: devStack,
            availableForAIMB: available,
            reclaimableFromIdleMB: reclaimable
        )
    }

    // MARK: - Smart AI Advisor

    /// Check which models from the database fit alongside your current dev stack.
    func modelsToFitAlongside() -> [(model: AIModel, quant: AIQuantization, fits: Bool, fitsAfterCleanup: Bool)] {
        let available = availableForAIMB
        let afterCleanup = available + reclaimableFromIdleMB

        return aiModelDatabase.compactMap { model in
            // Find best quantization that could fit
            let sorted = model.quantizations.sorted { $0.ramRequiredMB < $1.ramRequiredMB }
            guard let best = sorted.last(where: { $0.ramRequiredMB <= afterCleanup })
                    ?? sorted.first else { return nil }
            let fits = best.ramRequiredMB <= available
            let fitsAfterCleanup = best.ramRequiredMB <= afterCleanup
            return (model, best, fits, fitsAfterCleanup)
        }
    }

    /// Recommend the best quantization for a model given current available memory.
    func recommendQuant(for model: AIModel) -> (quant: AIQuantization, headroomMB: Int)? {
        let available = availableForAIMB + reclaimableFromIdleMB
        let sorted = model.quantizations.sorted { $0.ramRequiredMB < $1.ramRequiredMB }

        // Find the highest quality quant that fits with at least 10% headroom
        for quant in sorted.reversed() {
            let headroom = available - quant.ramRequiredMB
            if headroom >= quant.ramRequiredMB / 10 {  // 10% headroom minimum
                return (quant, headroom)
            }
        }

        // Fall back to lowest quant if it fits at all
        if let lowest = sorted.first, lowest.ramRequiredMB <= available {
            return (lowest, available - lowest.ramRequiredMB)
        }

        return nil
    }

    /// Predict whether loading a model will cause memory pressure.
    func predictLoadImpact(modelSizeMB: Int) -> LoadPrediction {
        let afterLoad = gpuAllocatedMB + modelSizeMB
        let ceilingUsage = Double(afterLoad) / Double(gpuCeilingMB)

        if modelSizeMB > availableForAIMB + reclaimableFromIdleMB {
            return .willNotFit(shortfallMB: modelSizeMB - availableForAIMB - reclaimableFromIdleMB)
        }
        if modelSizeMB > availableForAIMB && reclaimableFromIdleMB > 0 {
            return .fitsAfterUnload(unloadMB: modelSizeMB - availableForAIMB)
        }
        if ceilingUsage > 0.9 {
            return .tight(usagePercent: Int(ceilingUsage * 100))
        }
        return .comfortable(headroomMB: availableForAIMB - modelSizeMB)
    }

    /// Detect VRAM fragmentation by comparing expected vs actual availability.
    var fragmentationSuspected: Bool {
        // If Ollama reports 0 models but GPU still shows high allocation, fragmentation likely
        guard ollamaModelsMB == 0 else { return false }
        let unexplainedGPU = gpuAllocatedMB - devStackMB
        return unexplainedGPU > 512  // >512MB unexplained GPU allocation
    }

    var fragmentationWarning: String? {
        guard fragmentationSuspected else { return nil }
        let unexplained = gpuAllocatedMB - devStackMB
        let unexplainedStr = unexplained >= 1024
            ? String(format: "%.1f GB", Double(unexplained) / 1024)
            : "\(unexplained) MB"
        return "\(unexplainedStr) of GPU memory may be fragmented. Restart Ollama to reclaim."
    }
}

enum LoadPrediction {
    case comfortable(headroomMB: Int)
    case tight(usagePercent: Int)
    case fitsAfterUnload(unloadMB: Int)
    case willNotFit(shortfallMB: Int)

    var icon: String {
        switch self {
        case .comfortable: return "checkmark.circle.fill"
        case .tight: return "exclamationmark.triangle.fill"
        case .fitsAfterUnload: return "arrow.uturn.down.circle.fill"
        case .willNotFit: return "xmark.circle.fill"
        }
    }

    var description: String {
        switch self {
        case .comfortable(let mb):
            let s = mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
            return "Fits comfortably — \(s) headroom"
        case .tight(let pct):
            return "Tight — will use \(pct)% of GPU ceiling"
        case .fitsAfterUnload(let mb):
            let s = mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
            return "Fits after unloading \(s) of idle models"
        case .willNotFit(let mb):
            let s = mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
            return "Won't fit — \(s) short"
        }
    }
}
