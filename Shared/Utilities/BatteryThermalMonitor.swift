import Foundation
import IOKit.ps

public final class BatteryThermalMonitor: ObservableObject {
    public static let shared = BatteryThermalMonitor()

    @Published public private(set) var onBattery: Bool = false
    @Published public private(set) var batteryLevelPercent: Int = 100
    @Published public private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    private var timer: Timer?

    private init() {
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    private func update() {
        thermalState = ProcessInfo.processInfo.thermalState
        let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as NSArray
        if let source = sources.firstObject as CFTypeRef? {
            if let desc = IOPSGetPowerSourceDescription(blob, source).takeUnretainedValue() as? [String: Any] {
                if let ps = desc[kIOPSPowerSourceStateKey as String] as? String {
                    onBattery = ps == kIOPSBatteryPowerValue
                }
                if let cap = desc[kIOPSCurrentCapacityKey as String] as? Int, let max = desc[kIOPSMaxCapacityKey as String] as? Int, max > 0 {
                    batteryLevelPercent = Int((Double(cap) / Double(max)) * 100.0)
                }
            }
        }
    }
}
