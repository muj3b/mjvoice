import Cocoa
import SwiftUI
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let dashboardController = DashboardWindowController.shared
    private lazy var menuController = MenuBarController(openDashboard: { [weak self] in
        self?.dashboardController.show()
    })
    private var onboardingWindow: NSWindow?
    private let overlayWindow = DictationOverlayWindow()
    private var overlayRepositionTimer: DispatchSourceTimer?
    private var currentOverlayDisplayID: CGDirectDisplayID?
    private var screenParamObserver: NSObjectProtocol?
    private var spaceChangeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupStatusItem()
        ensureAccessibilityPermissions()
        GlobalHotkeyManager.shared.configure(mode: PreferencesStore.shared.current.pttMode)
        GlobalHotkeyManager.shared.registerDefaultHotkey()
        SecureInputMonitor.shared.start()

        if !PreferencesStore.shared.current.hasCompletedOnboarding {
            showOnboarding(resetProgress: false)
        } else {
            dashboardController.show()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(onPTTStart), name: .pttStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onPTTStop), name: .pttStop, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onPTTToggle), name: .pttToggle, object: nil)

        screenParamObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.repositionToActiveScreenIfNeeded()
            }
        }
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.repositionToActiveScreenIfNeeded()
            }
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopOverlayRepositioning()
        if let token = screenParamObserver { NotificationCenter.default.removeObserver(token) }
        if let token = spaceChangeObserver { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dashboardController.show()
        return true
    }

    @objc private func onPTTStart() {
        showOverlay()
        startOverlayRepositioning()
        AudioEngine.shared.startPTT()
    }

    @objc private func onPTTStop() {
        AudioEngine.shared.stopPTT()
        stopOverlayRepositioning()
    }

    @objc private func onPTTToggle() {
        if AudioEngine.shared.isRunning {
            AudioEngine.shared.stopPTT()
            stopOverlayRepositioning()
        } else {
            showOverlay()
            startOverlayRepositioning()
            AudioEngine.shared.startPTT()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "mjvoice")
        }
        statusItem.menu = menuController.menu
    }

    private func ensureAccessibilityPermissions() {
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(opts)
        if !trusted {
            let alert = NSAlert()
            alert.messageText = "Accessibility Access Required"
            alert.informativeText = "mjvoice needs Accessibility permissions to listen for global hotkeys and function key events. Go to System Settings → Privacy & Security → Accessibility and enable mjvoice."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Quit")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            } else {
                NSApp.terminate(nil)
            }
        }
    }

    func showOnboarding(resetProgress: Bool = false) {
        if resetProgress {
            PreferencesStore.shared.update { $0.hasCompletedOnboarding = false }
        }
        onboardingWindow?.close()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Welcome to mjvoice"
        window.contentView = NSHostingView(rootView: OnboardingView())
        window.makeKeyAndOrderFront(nil)
        window.level = .floating
        onboardingWindow = window
    }

    func dismissOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
        dashboardController.show()
    }

    private func repositionToActiveScreenIfNeeded() {
        // Only reposition when overlay is visible (dictation active)
        guard overlayWindow.isVisible else { return }
        guard let screen = activeScreen(), let newID = displayID(for: screen) else { return }
        if currentOverlayDisplayID != newID {
            overlayWindow.present(on: screen)
            currentOverlayDisplayID = newID
        }
    }

    private func showOverlay() {
        guard let screen = activeScreen() else { return }
        overlayWindow.present(on: screen)
        currentOverlayDisplayID = displayID(for: screen)
    }

    private func activeScreen() -> NSScreen? {
        if let focused = screenForFocusedWindow() { return focused }
        if let screen = NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen { return screen }
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return CGDirectDisplayID(number.uint32Value)
        }
        return nil
    }

    private func startOverlayRepositioning() {
        stopOverlayRepositioning()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.3, repeating: 0.3)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.repositionToActiveScreenIfNeeded()
            }
        }
        overlayRepositionTimer = timer
        timer.resume()
    }

    private func stopOverlayRepositioning() {
        overlayRepositionTimer?.cancel()
        overlayRepositionTimer = nil
    }

    private func screenForFocusedWindow() -> NSScreen? {
        guard AXIsProcessTrusted() else { return nil }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var windowRef: CFTypeRef?
        var error = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        if error != .success || windowRef == nil {
            error = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &windowRef)
        }
        guard error == .success, let win = windowRef else { return nil }
        // Ensure it's an AXUIElement
        guard CFGetTypeID(win) == AXUIElementGetTypeID() else { return nil }
        let windowElement = unsafeBitCast(win, to: AXUIElement.self)

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let axPos = posRef, let axSize = sizeRef,
              CFGetTypeID(axPos) == AXValueGetTypeID(), CFGetTypeID(axSize) == AXValueGetTypeID() else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(axPos as! AXValue, .cgPoint, &origin)
        AXValueGetValue(axSize as! AXValue, .cgSize, &size)

        let rect = CGRect(origin: origin, size: size)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) }
    }
}
