import AppKit
import SwiftUI

final class MenuBarController {
    let menu: NSMenu = NSMenu()

    private var isPaused: Bool = false
    private let openDashboardHandler: () -> Void

    init(openDashboard: @escaping () -> Void) {
        self.openDashboardHandler = openDashboard
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let statusTitle = isPaused ? "Resume mjvoice" : "Pause mjvoice"
        let toggleItem = NSMenuItem(title: statusTitle, action: #selector(toggleActive), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let offline = PreferencesStore.shared.current.offlineMode
        let offlineItem = NSMenuItem(title: offline ? "Offline Mode: On" : "Offline Mode: Off", action: #selector(toggleOffline), keyEquivalent: "")
        offlineItem.target = self
        menu.addItem(offlineItem)

        menu.addItem(NSMenuItem.separator())
        let dashboardItem = NSMenuItem(title: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "d")
        dashboardItem.keyEquivalentModifierMask = [.command]
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit mjvoice", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func toggleActive() {
        isPaused.toggle()
        rebuildMenu()
        NotificationCenter.default.post(name: .mjvoiceActiveChanged, object: !isPaused)
    }

    @objc private func toggleOffline() {
        PreferencesStore.shared.update { $0.offlineMode.toggle() }
        rebuildMenu()
        NotificationCenter.default.post(name: .mjvoiceOfflineModeChanged, object: PreferencesStore.shared.current.offlineMode)
    }

    @objc private func openPreferences() {
        PreferencesWindowController.shared.show()
    }

    @objc private func openDashboard() {
        openDashboardHandler()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    static let mjvoiceActiveChanged = Notification.Name("mjvoiceActiveChanged")
    static let mjvoiceOfflineModeChanged = Notification.Name("mjvoiceOfflineModeChanged")
}
