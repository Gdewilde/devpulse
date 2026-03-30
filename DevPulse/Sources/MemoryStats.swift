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
