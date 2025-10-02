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
    private let hudWindow = MicHUDWindow()
    private var hudFollowTimer: DispatchSourceTimer?

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
        NotificationCenter.default.addObserver(self, selector: #selector(onHUDState(_:)), name: .hudStateChanged, object: nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dashboardController.show()
        return true
    }

    @objc private func onPTTStart() {
        showHUD()
        AudioEngine.shared.startPTT()
        startHUDFollow()
    }

    @objc private func onPTTStop() {
        AudioEngine.shared.stopPTT()
        stopHUDFollow()
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
        let mouse = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        guard let screen = targetScreen else { return }

        let visible = screen.visibleFrame
        let clampedX = min(max(mouse.x, visible.minX + 100), visible.maxX - 100)
        let clampedY = min(max(mouse.y, visible.minY + 140), visible.maxY - 60)
        let anchor = NSPoint(x: clampedX, y: clampedY)

        hudWindow.show(anchoringTo: anchor, on: screen)
    }

    private func startHUDFollow() {
        hudFollowTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + .milliseconds(120), repeating: .milliseconds(120))
        timer.setEventHandler { [weak self] in
            guard let self, AudioEngine.shared.isRunning else { return }
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
            guard let screen else { return }
            self.hudWindow.show(anchoringTo: mouse, on: screen)
        }
        timer.resume()
        hudFollowTimer = timer
    }

    private func stopHUDFollow() {
        hudFollowTimer?.cancel()
        hudFollowTimer = nil
    }
}
