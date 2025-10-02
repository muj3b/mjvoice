import AppKit

final class MicHUDWindow: NSPanel {
    private let visualEffect = NSVisualEffectView()
    private let hudView = MicHUDView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
    private let windowSize = NSSize(width: 110, height: 110)
    private var lastAnchor: NSPoint?

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: windowSize),
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .screenSaver
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true

        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .withinWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = windowSize.width / 2
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.6).cgColor
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        visualEffect.layer?.borderWidth = 1
        visualEffect.frame = NSRect(origin: .zero, size: windowSize)

        // Inner shadow
        let shadowLayer = CALayer()
        shadowLayer.frame = CGRect(origin: .zero, size: windowSize).insetBy(dx: -12, dy: -12)
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOffset = .zero
        shadowLayer.shadowRadius = 10
        shadowLayer.shadowOpacity = 0.3
        visualEffect.layer?.addSublayer(shadowLayer)

        contentView = visualEffect
        visualEffect.addSubview(hudView)
        hudView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hudView.centerXAnchor.constraint(equalTo: visualEffect.centerXAnchor),
            hudView.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
            hudView.widthAnchor.constraint(equalToConstant: 80),
            hudView.heightAnchor.constraint(equalToConstant: 80)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(onLevel(_:)), name: .audioLevelDidUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onState(_:)), name: .hudStateChanged, object: nil)
    }

    func show(anchoringTo point: NSPoint, on screen: NSScreen) {
        let clamped = clamp(point, in: screen)
        if let last = lastAnchor {
            lastAnchor = clamped
            animate(to: clamped)
        } else {
            lastAnchor = clamped
            position(at: clamped)
            alphaValue = 0
            orderFrontRegardless()
            animator().alphaValue = 1
        }
    }

    func hide() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            self.animator().alphaValue = 0
        } completionHandler: {
            self.alphaValue = 1
            self.lastAnchor = nil
            self.orderOut(nil)
        }
    }

    private func animate(to anchor: NSPoint) {
        let frame = frame(for: anchor)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            self.animator().setFrame(frame, display: false)
        }
        if !isVisible {
            orderFrontRegardless()
        }
    }

    private func position(at anchor: NSPoint) {
        setFrame(frame(for: anchor), display: false)
        orderFrontRegardless()
    }

    @objc private func onLevel(_ n: Notification) {
        if let level = n.object as? CGFloat { hudView.update(level: level) }
    }

    @objc private func onState(_ n: Notification) {
        if let s = n.object as? MicHUDView.State { hudView.state = s }
    }

    private func frame(for anchor: NSPoint) -> NSRect {
        NSRect(x: anchor.x - windowSize.width / 2,
               y: anchor.y - windowSize.height / 2,
               width: windowSize.width,
               height: windowSize.height)
    }

    private func clamp(_ point: NSPoint, in screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        let margin: CGFloat = 84
        let x = min(max(point.x, visible.minX + margin), visible.maxX - margin)
        let y = min(max(point.y, visible.minY + margin), visible.maxY - margin)
        return NSPoint(x: x, y: y)
    }
}

extension Notification.Name {
    static let audioLevelDidUpdate = Notification.Name("audioLevelDidUpdate")
    static let hudStateChanged = Notification.Name("hudStateChanged")
}
