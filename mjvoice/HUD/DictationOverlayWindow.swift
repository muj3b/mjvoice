import AppKit
import SwiftUI

final class DictationOverlayWindow: NSPanel {
    private let viewModel = DictationOverlayViewModel()
    private let hostingController: NSHostingController<DictationOverlayView>
    private var currentScreen: NSScreen?
    private var hideWorkItem: DispatchWorkItem?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        hostingController = NSHostingController(rootView: DictationOverlayView(model: viewModel))
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        ignoresMouseEvents = true

        contentView = hostingController.view
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

        NotificationCenter.default.addObserver(self, selector: #selector(onOverlayState(_:)), name: .hudStateChanged, object: nil)
    }

    convenience init() {
        self.init(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
    }

    func present(on screen: NSScreen) {
        currentScreen = screen
        setFrame(screen.frame, display: true)
        hostingController.view.frame = NSRect(origin: .zero, size: screen.frame.size)
        if !isVisible {
            orderFrontRegardless()
        }
        cancelHide()
        viewModel.state = .listening
    }

    func hide() {
        viewModel.state = .idle
        scheduleHide(after: 0.2)
    }

    func updateState(_ state: DictationOverlayState) {
        if state == .idle {
            viewModel.state = .idle
            scheduleHide(after: 0.18)
        } else {
            viewModel.state = state
            cancelHide()
            ensureVisible()
        }
    }

    private func ensureVisible() {
        guard let screen = currentScreen ?? NSScreen.main else { return }
        if frame != screen.frame {
            setFrame(screen.frame, display: true)
            hostingController.view.frame = NSRect(origin: .zero, size: screen.frame.size)
        }
        if !isVisible {
            orderFrontRegardless()
        }
    }

    @objc private func onOverlayState(_ notification: Notification) {
        guard let state = notification.object as? DictationOverlayState else { return }
        DispatchQueue.main.async { [weak self] in
            self?.updateState(state)
        }
    }

    private func scheduleHide(after delay: TimeInterval) {
        cancelHide()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.orderOut(nil)
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }
}

extension Notification.Name {
    static let audioLevelDidUpdate = Notification.Name("audioLevelDidUpdate")
    static let hudStateChanged = Notification.Name("hudStateChanged")
}
