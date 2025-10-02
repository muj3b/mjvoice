import Foundation
import IOKit
import IOKit.hid

final class SecureInputMonitor {
    static let shared = SecureInputMonitor()
    private var timer: DispatchSourceTimer?
    private(set) var isSecureInputOn: Bool = false

    private init() {}

    func start() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        t.schedule(deadline: .now(), repeating: .seconds(1))
        t.setEventHandler { [weak self] in
            let on = Self.checkSecureInput()
            if on != self?.isSecureInputOn {
                self?.isSecureInputOn = on
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .secureInputChanged, object: on)
                }
            }
        }
        t.resume()
        timer = t
    }

    static func checkSecureInput() -> Bool {
        var masterPort: mach_port_t = 0
        let kerr = IOMasterPort(mach_port_t(MACH_PORT_NULL), &masterPort)
        guard kerr == KERN_SUCCESS else { return false }
        let matching = IOServiceMatching("IOHIDSystem")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(masterPort, matching, &iterator) == KERN_SUCCESS else {
            return false
        }
        var entry: io_object_t = IOIteratorNext(iterator)
        var isOn = false
        while entry != 0 {
            if let value = IORegistryEntryCreateCFProperty(entry, "HIDSecureEventInput" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool {
                isOn = value
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
        return isOn
    }
}

extension Notification.Name {
    static let secureInputChanged = Notification.Name("secureInputChanged")
}
