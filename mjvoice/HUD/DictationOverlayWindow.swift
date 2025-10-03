import AppKit
import SwiftUI

final class DictationOverlayWindow: NSPanel {
    private let viewModel = DictationOverlayViewModel()
    private let hostingController: NSHostingController<DictationOverlayView>
    private var currentScreen: NSScreen?

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

        NotificationCenter.default.addObserver(self, selector: #selector(onAudioLevel(_:)), name: .audioLevelDidUpdate, object: nil)
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
        viewModel.state = .listening
    }

    func hide() {
        viewModel.state = .idle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            if self.viewModel.state == .idle {
                self.orderOut(nil)
            }
        }
    }

    func updateState(_ state: DictationOverlayState) {
        viewModel.state = state
        if state == .idle {
            hide()
        } else {
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

    @objc private func onAudioLevel(_ notification: Notification) {
        guard let level = notification.object as? CGFloat else { return }
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.audioLevel = level
        }
    }

    @objc private func onOverlayState(_ notification: Notification) {
        guard let state = notification.object as? DictationOverlayState else { return }
        DispatchQueue.main.async { [weak self] in
            self?.updateState(state)
        }
    }
}

extension Notification.Name {
    static let audioLevelDidUpdate = Notification.Name("audioLevelDidUpdate")
    static let hudStateChanged = Notification.Name("hudStateChanged")
}
