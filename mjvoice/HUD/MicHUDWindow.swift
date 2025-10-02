import AppKit

final class MicHUDWindow: NSPanel {
    private let visualEffect = NSVisualEffectView()
    private let hudView = MicHUDView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80),
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true

        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .withinWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 40
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.backgroundColor = NSColor.systemGray.withAlphaComponent(0.6).cgColor
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        visualEffect.layer?.borderWidth = 1

        // Inner shadow
        let shadowLayer = CALayer()
        shadowLayer.frame = visualEffect.bounds.insetBy(dx: -10, dy: -10)
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

    func show(near point: NSPoint) {
        setFrameTopLeftPoint(NSPoint(x: point.x - 40, y: point.y + 40))
        orderFront(nil)
    }

    func hide() {
        orderOut(nil)
    }

    @objc private func onLevel(_ n: Notification) {
        if let level = n.object as? CGFloat { hudView.update(level: level) }
    }

    @objc private func onState(_ n: Notification) {
        if let s = n.object as? MicHUDView.State { hudView.state = s }
    }
}

extension Notification.Name {
    static let audioLevelDidUpdate = Notification.Name("audioLevelDidUpdate")
    static let hudStateChanged = Notification.Name("hudStateChanged")
}
