import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let dashboardController = DashboardWindowController.shared
    private lazy var menuController = MenuBarController(openDashboard: { [weak self] in
        self?.dashboardController.show()
    })
    private var onboardingWindow: NSWindow?
    private let hudWindow = MicHUDWindow()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
        NotificationCenter.default.addObserver(self, selector: #selector(onHUDState(_:)), name: .hudStateChanged, object: nil)
    }

    @objc private func onPTTStart() {
        showHUD()
        AudioEngine.shared.startPTT()
    }

    @objc private func onPTTStop() {
        AudioEngine.shared.stopPTT()
    }

    @objc private func onPTTToggle() {
        if AudioEngine.shared.isRunning { AudioEngine.shared.stopPTT() }
        else { AudioEngine.shared.startPTT() }
    }

    @objc private func onHUDState(_ notification: Notification) {
        guard let state = notification.object as? MicHUDView.State else { return }
        if state == .idle && !AudioEngine.shared.isRunning {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.hudWindow.hide()
            }
        }
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

    private func showHUD() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let point = NSPoint(x: frame.minX + 120, y: frame.maxY - 80)
        hudWindow.show(near: point)
    }
}
