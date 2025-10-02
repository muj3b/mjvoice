import AppKit

final class TextInserter {
    enum Outcome {
        case inserted(bundleID: String?)
        case clipboard
        case notes
    }

    static let shared = TextInserter()
    private init() {}

    @discardableResult
    func insert(text: String) -> Outcome {
        guard !SecureInputMonitor.shared.isSecureInputOn else {
            copyToClipboard(text)
            notifyClipboardFallback()
            return .clipboard
        }

        if let focus = currentFocus() {
            if insertViaAX(text, target: focus.element) {
                return .inserted(bundleID: focus.bundleID)
            }
            if pasteboardFallback(text) {
                return .inserted(bundleID: focus.bundleID)
            }
        }

        copyToClipboard(text)
        notifyClipboardFallback()
        return .clipboard
    }

    @discardableResult
    func insert(text: String, prefs: UserPreferences) -> Outcome {
        let appBundleId = getCurrentAppBundleId()
        let formatted = TextFormatter.shared.format(text: text, prefs: prefs, appBundleId: appBundleId)
        return insert(text: formatted)
    }

    private func insertViaAX(_ text: String, target: AXUIElement) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        var selectedRange: CFTypeRef?
        let hasRange = AXUIElementCopyAttributeValue(target, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success
        let newString: CFString = text as CFString
        if hasRange {
            if AXUIElementSetAttributeValue(target, kAXSelectedTextAttribute as CFString, newString) == .success {
                return true
            }
        }
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
            pb.clearContents()
            if let items = existing { pb.writeObjects(items) }
        }
        return success
    }

    private func synthesizeCmdV() -> Bool {
        let src = CGEventSource(stateID: .hidSystemState)
        let keyVDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        keyVDown?.flags = .maskCommand
        let keyVUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        keyVUp?.flags = .maskCommand
        keyVDown?.post(tap: .cghidEventTap)
        keyVUp?.post(tap: .cghidEventTap)
        return true
    }

    private func currentFocus() -> (element: AXUIElement, bundleID: String?)? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let res = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard res == .success, let focusedElement = focused else { return nil }
        let target = unsafeBitCast(focusedElement, to: AXUIElement.self)
        var pid: pid_t = 0
        AXUIElementGetPid(target, &pid)
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        return (target, bundleID)
    }

    private func getCurrentAppBundleId() -> String? {
        currentFocus()?.bundleID
    }

    private func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func notifyClipboardFallback() {
        let notification = NSUserNotification()
        notification.title = "Dictation copied to clipboard"
        notification.informativeText = "mjvoice saved your transcript because no editable field was focused."
        NSUserNotificationCenter.default.deliver(notification)
    }
}
