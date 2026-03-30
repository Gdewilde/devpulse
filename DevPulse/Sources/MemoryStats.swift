import Foundation
import Darwin

struct MemoryStats {
    let totalRAM: UInt64
    let freePages: UInt64
    let activePages: UInt64
    let inactivePages: UInt64
    let wiredPages: UInt64
    let compressedPages: UInt64
    let pageSize: UInt64
    let swapUsedMB: Double
    let swapTotalMB: Double

    var totalGB: Double { Double(totalRAM) / 1_073_741_824 }
    var freeBytes: UInt64 { freePages * pageSize }
    var activeBytes: UInt64 { activePages * pageSize }
    var inactiveBytes: UInt64 { inactivePages * pageSize }
    var wiredBytes: UInt64 { wiredPages * pageSize }
    var compressedBytes: UInt64 { compressedPages * pageSize }

    var usedBytes: UInt64 { activeBytes + wiredBytes + compressedBytes }
    var usedGB: Double { Double(usedBytes) / 1_073_741_824 }
    var freeGB: Double { Double(freeBytes + inactiveBytes) / 1_073_741_824 }
    var compressedGB: Double { Double(compressedBytes) / 1_073_741_824 }
    var swapUsedGB: Double { swapUsedMB / 1024 }

    var usedPercent: Double { Double(usedBytes) / Double(totalRAM) * 100 }

    var status: HealthStatus {
        if swapUsedGB >= 30 || usedPercent >= 90 { return .critical }
        if swapUsedGB >= 10 || usedPercent >= 75 { return .warning }
        return .healthy
    }

    static func current() -> MemoryStats {
        let totalRAM = UInt64(ProcessInfo.processInfo.physicalMemory)

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let pageSize = UInt64(vm_kernel_page_size)

        let hostPort = mach_host_self()
        let result = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(hostPort, HOST_VM_INFO64, intPtr, &count)
            }
        }
        mach_port_deallocate(mach_task_self_, hostPort)

        guard result == KERN_SUCCESS else {
            return MemoryStats(
                totalRAM: totalRAM, freePages: 0, activePages: 0,
                inactivePages: 0, wiredPages: 0, compressedPages: 0,
                pageSize: pageSize, swapUsedMB: 0, swapTotalMB: 0
            )
        }

        let swap = Self.getSwapUsage()

        return MemoryStats(
            totalRAM: totalRAM,
            freePages: UInt64(vmStats.free_count),
            activePages: UInt64(vmStats.active_count),
            inactivePages: UInt64(vmStats.inactive_count),
            wiredPages: UInt64(vmStats.wire_count),
            compressedPages: UInt64(vmStats.compressor_page_count),
            pageSize: pageSize,
            swapUsedMB: swap.used,
            swapTotalMB: swap.total
        )
    }

    private static func getSwapUsage() -> (used: Double, total: Double) {
        var swapUsage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0)
        guard result == 0 else { return (0, 0) }
        return (
            used: Double(swapUsage.xsu_used) / 1_048_576,
            total: Double(swapUsage.xsu_total) / 1_048_576
        )
    }
}

enum HealthStatus: String {
    case healthy
    case warning
    case critical

    var icon: String {
        switch self {
        case .healthy:  return "memorychip"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }

    var label: String {
        switch self {
        case .healthy:  return "Healthy"
        case .warning:  return "Warning"
        case .critical: return "Critical"
        }
    }
}

// MARK: - Swap Velocity (Phase 7)

class SwapTracker {
    private var history: [(timestamp: Date, swapMB: Double)] = []
    private let maxHistory = 60 // 60 samples = ~5 min at 5s intervals

    func record(swapGB: Double) {
        history.append((Date(), swapGB * 1024))
        if history.count > maxHistory { history.removeFirst() }
    }

    /// Swap growth rate in MB per hour
    var velocityMBPerHour: Double {
        guard history.count >= 6 else { return 0 } // need at least 30s of data
        let first = history.first!
        let last = history.last!
        let timeDelta = last.timestamp.timeIntervalSince(first.timestamp)
        guard timeDelta > 10 else { return 0 }
        let swapDelta = last.swapMB - first.swapMB
        return swapDelta / timeDelta * 3600
    }

    /// Predicted time until thrashing (swap > 80% of RAM), or nil if swap is decreasing
    func timeToThrashing(totalRAMGB: Double) -> TimeInterval? {
        let velocity = velocityMBPerHour
        guard velocity > 100 else { return nil } // growing > 100 MB/hr
        let currentSwapMB = history.last?.swapMB ?? 0
        let thrashingThresholdMB = totalRAMGB * 1024 * 0.8
        guard currentSwapMB < thrashingThresholdMB else { return nil } // already there
        let remainingMB = thrashingThresholdMB - currentSwapMB
        let hoursRemaining = remainingMB / velocity
        return hoursRemaining * 3600
    }

    var velocityFormatted: String {
        let v = velocityMBPerHour
        if abs(v) < 50 { return "stable" }
        let sign = v > 0 ? "+" : ""
        if abs(v) >= 1024 {
            return String(format: "%@%.1f GB/hr", sign, v / 1024)
        }
        return String(format: "%@%.0f MB/hr", sign, v)
    }
}

// MARK: - SSD Health (Phase 7)

struct SSDHealth {
    let dataWrittenGB: Int
    let dataReadGB: Int
    let powerOnHours: Int
    let available: Bool

    var dataWrittenFormatted: String {
        dataWrittenGB >= 1024
            ? String(format: "%.1f TB", Double(dataWrittenGB) / 1024)
            : "\(dataWrittenGB) GB"
    }
}

/// Read SSD health data from system_profiler (no admin required)
func getSSDHealth() -> SSDHealth {
    let pipe = Pipe()
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    proc.arguments = ["SPNVMeDataType", "-json"]
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice

    do { try proc.run() } catch {
        return SSDHealth(dataWrittenGB: 0, dataReadGB: 0, powerOnHours: 0, available: false)
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let nvme = json["SPNVMeDataType"] as? [[String: Any]],
          let disk = nvme.first else {
        return SSDHealth(dataWrittenGB: 0, dataReadGB: 0, powerOnHours: 0, available: false)
    }

    // Parse data written — format varies: "123.45 TB" or "456.78 GB"
    let writtenStr = disk["spnvme_databyteswritten"] as? String ?? ""
    let readStr = disk["spnvme_databytesread"] as? String ?? ""

    return SSDHealth(
        dataWrittenGB: parseStorageSize(writtenStr),
        dataReadGB: parseStorageSize(readStr),
        powerOnHours: 0, // Not always available
        available: true
    )
}

private func parseStorageSize(_ s: String) -> Int {
    let trimmed = s.trimmingCharacters(in: .whitespaces)
    if trimmed.hasSuffix("TB") {
        let num = Double(trimmed.dropLast(3).trimmingCharacters(in: .whitespaces)) ?? 0
        return Int(num * 1024)
    } else if trimmed.hasSuffix("GB") {
        let num = Double(trimmed.dropLast(3).trimmingCharacters(in: .whitespaces)) ?? 0
        return Int(num)
    }
    return 0
}
