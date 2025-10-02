import AppKit

final class MicHUDView: NSView {
    enum State { case idle, listening, thinking, inserting, error }

    private let ringLayer = CAShapeLayer()
    private var displayLink: CVDisplayLink?
    private var level: CGFloat = 0.0
    var state: State = .idle { didSet { updateAppearance() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = frameRect.width / 2
        setupRing()
        setupDisplayLink()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupRing() {
        let path = NSBezierPath(ovalIn: bounds.insetBy(dx: 4, dy: 4))
        if #available(macOS 14.0, *) {
            ringLayer.path = path.cgPath
        } else {
            // Fallback on earlier versions
        }
        ringLayer.strokeColor = NSColor.controlAccentColor.cgColor
        ringLayer.lineWidth = 3
        ringLayer.fillColor = NSColor.clear.cgColor
        ringLayer.strokeEnd = 0.1
        layer?.addSublayer(ringLayer)
    }

    private func setupDisplayLink() {
        var dl: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&dl)
        displayLink = dl
        if let displayLink {
            CVDisplayLinkSetOutputCallback(displayLink, { (_, _, _, _, _, userInfo) -> CVReturn in
                let unmanaged = Unmanaged<MicHUDView>.fromOpaque(userInfo!)
                unmanaged.takeUnretainedValue().tick()
                return kCVReturnSuccess
            }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
            CVDisplayLinkStart(displayLink)
        }
    }

    func update(level: CGFloat) {
        self.level = min(max(level, 0), 1)
    }

    private func tick() {
        DispatchQueue.main.async {
            let eased = 0.15 * self.level + 0.85 * self.ringLayer.strokeEnd
            self.ringLayer.strokeEnd = eased
            switch self.state {
            case .idle:
                self.ringLayer.opacity = 0.4
            case .listening:
                self.ringLayer.opacity = 1.0
            case .thinking:
                self.ringLayer.opacity = 0.8
            case .inserting:
                self.ringLayer.opacity = 1.0
            case .error:
                self.ringLayer.strokeColor = NSColor.systemRed.cgColor
                self.ringLayer.opacity = 1.0
            }
        }
    }

    private func updateAppearance() {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.duration = 0.15
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        switch state {
        case .idle:
            ringLayer.add(animation, forKey: "opacity")
            ringLayer.opacity = 0.4
            ringLayer.strokeColor = NSColor.systemGray.cgColor
        case .listening:
            ringLayer.add(animation, forKey: "opacity")
            ringLayer.opacity = 1.0
            ringLayer.strokeColor = NSColor.controlAccentColor.cgColor
        case .thinking:
            ringLayer.add(animation, forKey: "opacity")
            ringLayer.opacity = 0.8
            ringLayer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        case .inserting:
            ringLayer.add(animation, forKey: "opacity")
            ringLayer.opacity = 1.0
            ringLayer.strokeColor = NSColor.controlAccentColor.cgColor
        case .error:
            ringLayer.add(animation, forKey: "opacity")
            ringLayer.strokeColor = NSColor.systemRed.cgColor
            ringLayer.opacity = 1.0
        }
    }
}
