import AppKit

final class TextInserter {
    static let shared = TextInserter()
    private init() {}

    func insert(text: String) {
        guard !SecureInputMonitor.shared.isSecureInputOn else { return }
        if insertViaAX(text) { return }
        if pasteboardFallback(text) { return }
        _ = synthesizeTyping(text)
    }

    func insert(text: String, prefs: UserPreferences) {
        let appBundleId = getCurrentAppBundleId()
        let formatted = TextFormatter.shared.format(text: text, prefs: prefs, appBundleId: appBundleId)
        insert(text: formatted)
    }

    private func insertViaAX(_ text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let res = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard res == .success, let focusedElement = focused else { return false }
        let target = unsafeBitCast(focusedElement, to: AXUIElement.self)

        // Try to get current value and selection range
        var selectedRange: CFTypeRef?
        let hasRange = AXUIElementCopyAttributeValue(target, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success
        var newString: CFString = text as CFString
        if hasRange {
            // Replace selected range by setting attributed text is not always supported; try kAXSelectedTextAttribute
            if AXUIElementSetAttributeValue(target, kAXSelectedTextAttribute as CFString, newString) == .success {
                return true
            }
        }
        // If cannot set selected text, try setting value directly for simple text fields
        if AXUIElementSetAttributeValue(target, kAXValueAttribute as CFString, newString) == .success {
            return true
        }
        return false
    }

    private func pasteboardFallback(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        let existing = pb.pasteboardItems
        pb.clearContents()
        pb.setString(text, forType: .string)
        let success = synthesizeCmdV()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // restore
            pb.clearContents()
            if let items = existing { pb.writeObjects(items) }
        }
        return success
    }

    private func synthesizeCmdV() -> Bool {
        let src = CGEventSource(stateID: .hidSystemState)
        let keyVDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true) // v
        keyVDown?.flags = .maskCommand
        let keyVUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        keyVUp?.flags = .maskCommand
        keyVDown?.post(tap: .cghidEventTap)
        keyVUp?.post(tap: .cghidEventTap)
        return true
    }

    private func synthesizeTyping(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if let ev = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                ev.keyboardSetUnicodeString(stringLength: 1, unicodeString: [UInt16(scalar.value)])
                ev.post(tap: .cghidEventTap)
            }
        }
        return true
    }
    private func getCurrentAppBundleId() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let res = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard res == .success, let focusedElement = focused else { return nil }
        let target = unsafeBitCast(focusedElement, to: AXUIElement.self)

        var pid: pid_t = 0
        AXUIElementGetPid(target, &pid)
        let app = NSRunningApplication(processIdentifier: pid)
        return app?.bundleIdentifier
    }
}
