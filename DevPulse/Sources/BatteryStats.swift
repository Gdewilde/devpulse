import Foundation
import IOKit.ps

/// Power-source snapshot for travel-mode awareness. The CLI exposes this
/// in `devpulse watch` so long-running agent loops can react to battery
/// transitions (shrink context, checkpoint now, unload idle models).
struct BatteryStats {
    let percent: Int
    let onAC: Bool
    let isCharging: Bool
    /// Minutes to empty. nil on AC; -1 means the OS is still calculating.
    let timeToEmptyMinutes: Int?
    let lowPowerMode: Bool
}

func getBatteryStats() -> BatteryStats? {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
    guard let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }

    for source in sources {
        guard let dict = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else { continue }
        guard (dict[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }

        let maxCap = dict[kIOPSMaxCapacityKey] as? Int ?? 100
        let curCap = dict[kIOPSCurrentCapacityKey] as? Int ?? 0
        let percent = maxCap > 0 ? (curCap * 100 / maxCap) : 0
        let onAC = (dict[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let isCharging = dict[kIOPSIsChargingKey] as? Bool ?? false
        let ttE = dict[kIOPSTimeToEmptyKey] as? Int

        return BatteryStats(
            percent: percent,
            onAC: onAC,
            isCharging: isCharging,
            timeToEmptyMinutes: onAC ? nil : ttE,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }

    // Desktop Macs (Mac mini, iMac, Studio) — no internal battery.
    return nil
}
