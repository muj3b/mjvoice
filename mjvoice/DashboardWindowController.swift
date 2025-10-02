import AppKit
import SwiftUI

final class DashboardWindowController: NSWindowController {
    static let shared = DashboardWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "mjvoice"
        window.center()
        window.contentView = NSHostingView(rootView: DashboardView())
        window.tabbingMode = .preferred
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        window.contentView = NSHostingView(rootView: DashboardView())
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
