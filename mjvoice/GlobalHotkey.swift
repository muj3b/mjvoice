import Cocoa
import Carbon.HIToolbox

private func fourCharCode(_ string: String) -> OSType {
    var result: UInt32 = 0
    for scalar in string.utf16.prefix(4) {
        result = (result << 8) + UInt32(scalar)
    }
    return OSType(result)
}

final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private(set) var mode: PTTMode = .pressHold
    private var isLatched: Bool = false
    private var fnGlobalMonitor: Any?
    private var fnLocalMonitor: Any?
    private var fnPressed = false

    func configure(mode: PTTMode) {
        self.mode = mode
    }

    class func canRegister(hotkey: Hotkey) -> Bool {
        if hotkey.key.lowercased() == "fn" { return true }
        let mods = Self.modifiersFrom(hotkey.modifiers)
        let keyCode = Self.keyCodeFrom(name: hotkey.key)
        var hotKeyRef: EventHotKeyRef?
        var hotKeyID = EventHotKeyID(signature: fourCharCode("mjvo"), id: 1)
        let status = RegisterEventHotKey(keyCode, mods, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status == noErr {
            if let ref = hotKeyRef {
                UnregisterEventHotKey(ref)
            }
            return true
        } else {
            return false
        }
    }

    func registerDefaultHotkey() {
        unregister()
        let prefs = PreferencesStore.shared.current
        if prefs.hotkey.key.lowercased() == "fn" {
            registerFnMonitor()
            return
        }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var eventType2 = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            let kind = GetEventKind(event)
            if kind == UInt32(kEventHotKeyPressed) {
                GlobalHotkeyManager.shared.handlePressed()
            } else if kind == UInt32(kEventHotKeyReleased) {
                GlobalHotkeyManager.shared.handleReleased()
            }
            return noErr
        }, 2, [eventType, eventType2], nil, &eventHandler)
        let modifiers = Self.modifiersFrom(prefs.hotkey.modifiers)
        let keyCode = Self.keyCodeFrom(name: prefs.hotkey.key)

        var hotKeyID = EventHotKeyID(signature: fourCharCode("mjvo"), id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKeyRef = nil
        eventHandler = nil
        if let monitor = fnGlobalMonitor { NSEvent.removeMonitor(monitor); fnGlobalMonitor = nil }
        if let monitor = fnLocalMonitor { NSEvent.removeMonitor(monitor); fnLocalMonitor = nil }
        fnPressed = false
    }

    private func handlePressed() {
        switch mode {
        case .pressHold:
            NotificationCenter.default.post(name: .pttStart, object: nil)
        case .latch:
            isLatched.toggle()
            if isLatched { NotificationCenter.default.post(name: .pttStart, object: nil) }
            else { NotificationCenter.default.post(name: .pttStop, object: nil) }
        case .toggle:
            NotificationCenter.default.post(name: .pttToggle, object: nil)
        }
    }

    private func handleReleased() {
        if mode == .pressHold {
            NotificationCenter.default.post(name: .pttStop, object: nil)
        }
    }

    private static func modifiersFrom(_ mods: [String]) -> UInt32 {
        var mask: UInt32 = 0
        for m in mods {
            switch m.lowercased() {
            case "command": mask |= UInt32(cmdKey)
            case "option": mask |= UInt32(optionKey)
            case "control": mask |= UInt32(controlKey)
            case "shift": mask |= UInt32(shiftKey)
            case "fn": break
            default: break
            }
        }
        return mask
    }

    private static func keyCodeFrom(name: String) -> UInt32 {
        switch name.lowercased() {
        case "space": return UInt32(kVK_Space)
        case "a": return UInt32(kVK_ANSI_A)
        default: return UInt32(kVK_Space)
        }
    }

    private func registerFnMonitor() {
        fnLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFnEvent(event)
            return event
        }
        fnGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            self?.handleFnEvent(event)
        })
    }

    private func handleFnEvent(_ event: NSEvent) {
        guard event.keyCode == 63 else { return }
        let isDown = event.modifierFlags.contains(.function)
        if isDown && !fnPressed {
            fnPressed = true
            handlePressed()
        } else if !isDown && fnPressed {
            fnPressed = false
            handleReleased()
        }
    }
}

extension Notification.Name {
    static let pttStart = Notification.Name("pttStart")
    static let pttStop = Notification.Name("pttStop")
    static let pttToggle = Notification.Name("pttToggle")
}
