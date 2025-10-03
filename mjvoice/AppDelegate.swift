import Cocoa
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let dashboardController = DashboardWindowController.shared
    private lazy var menuController = MenuBarController(openDashboard: { [weak self] in
        self?.dashboardController.show()
    })
    private var onboardingWindow: NSWindow?
    private let overlayWindow = DictationOverlayWindow()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupStatusItem()
        requestAccessibilityTrustIfNeeded()
        GlobalHotkeyManager.shared.configure(mode: PreferencesStore.shared.current.pttMode)
        GlobalHotkeyManager.shared.registerDefaultHotkey()
        SecureInputMonitor.shared.start()

        if !PreferencesStore.shared.current.hasCompletedOnboarding {
            showOnboarding()
        } else {
            dashboardController.show()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(onPTTStart), name: .pttStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onPTTStop), name: .pttStop, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onPTTToggle), name: .pttToggle, object: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dashboardController.show()
        return true
    }

    @objc private func onPTTStart() {
        showOverlay()
        AudioEngine.shared.startPTT()
    }

    @objc private func onPTTStop() {
        AudioEngine.shared.stopPTT()
    }

    @objc private func onPTTToggle() {
        if AudioEngine.shared.isRunning { AudioEngine.shared.stopPTT() }
        else { AudioEngine.shared.startPTT() }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "mjvoice")
        }
        statusItem.menu = menuController.menu
    }

    private func requestAccessibilityTrustIfNeeded() {
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private func showOnboarding() {
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

    private func showOverlay() {
        guard let screen = activeScreen() else { return }
        overlayWindow.present(on: screen)
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main
    }
}
