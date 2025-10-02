import AppKit

final class MicHUDView: NSView {
    enum State { case idle, listening, thinking, inserting, error }

    private let bubbleLayer = CAShapeLayer()
    private let highlightLayer = CAShapeLayer()
    private let pulseLayer = CAShapeLayer()
    private var displayLink: CVDisplayLink?

    private var targetRadius: CGFloat = 36
    private var currentRadius: CGFloat = 36
    private var velocity: CGFloat = 0
    private var targetOffset: CGPoint = .zero
    private var currentOffset: CGPoint = .zero
    private var offsetVelocity: CGPoint = .zero
    private var orbitPhase: CGFloat = 0
    private var lastPulseTime: CFTimeInterval = 0
    private var lastLevel: CGFloat = 0

    private var targetLevel: CGFloat = 0
    private var smoothedLevel: CGFloat = 0

    private let minRadius: CGFloat = 28
    private let maxRadius: CGFloat = 96
    private let stiffness: CGFloat = 14
    private let damping: CGFloat = 9
    private let offsetStiffness: CGFloat = 10
    private let offsetDamping: CGFloat = 8

    var state: State = .idle { didSet { updateAppearance(animated: true) } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        setupLayers()
        setupDisplayLink()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupLayers() {
        guard let backing = layer else { return }
        backing.backgroundColor = NSColor.clear.cgColor

        pulseLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        pulseLayer.strokeColor = NSColor.clear.cgColor
        pulseLayer.opacity = 0
        backing.addSublayer(pulseLayer)

        bubbleLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
        bubbleLayer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
        bubbleLayer.lineWidth = 1.2
        bubbleLayer.shadowColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        bubbleLayer.shadowRadius = 18
        bubbleLayer.shadowOpacity = 0.5
        bubbleLayer.shadowOffset = .zero
        backing.addSublayer(bubbleLayer)

        highlightLayer.fillColor = NSColor.white.withAlphaComponent(0.2).cgColor
        highlightLayer.strokeColor = NSColor.clear.cgColor
        backing.addSublayer(highlightLayer)

        updatePaths(radius: currentRadius)
    }

    private func setupDisplayLink() {
        var dl: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&dl)
        displayLink = dl
        if let displayLink {
            CVDisplayLinkSetOutputCallback(displayLink, { (_, _, _, _, _, userInfo) -> CVReturn in
                guard let userInfo else { return kCVReturnError }
                let view = Unmanaged<MicHUDView>.fromOpaque(userInfo).takeUnretainedValue()
                view.tick()
                return kCVReturnSuccess
            }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
            CVDisplayLinkStart(displayLink)
        }
    }

    func update(level: CGFloat) {
        let clamped = min(max(level, 0), 1)
        targetLevel = clamped
        if (clamped > 0.72 && lastLevel <= 0.72) || clamped > 0.9 {
            triggerPulse()
        }
        lastLevel = clamped
    }

    private func tick() {
        let frameDuration = 1.0 / 120.0
        let dt = CGFloat(frameDuration)

        let rampUp: CGFloat = 12
        let rampDown: CGFloat = 4
        let rate = targetLevel > smoothedLevel ? rampUp : rampDown
        smoothedLevel += (targetLevel - smoothedLevel) * min(1, rate * dt)
        smoothedLevel = min(max(smoothedLevel, 0), 1)
        targetRadius = radius(for: smoothedLevel)

        let displacement = targetRadius - currentRadius
        let acceleration = stiffness * displacement - damping * velocity
        velocity += acceleration * dt
        currentRadius += velocity * dt
        currentRadius = max(min(currentRadius, maxRadius), minRadius)

        orbitPhase += dt * (2.0 + smoothedLevel * 6.0)
        let sway = sin(orbitPhase) * 16 * smoothedLevel
        let bob = cos(orbitPhase * 0.75) * 9 * smoothedLevel
        targetOffset = CGPoint(x: sway, y: bob - (36 * smoothedLevel))

        let offsetDelta = CGPoint(x: targetOffset.x - currentOffset.x, y: targetOffset.y - currentOffset.y)
        offsetVelocity.x += (offsetStiffness * offsetDelta.x - offsetDamping * offsetVelocity.x) * dt
        offsetVelocity.y += (offsetStiffness * offsetDelta.y - offsetDamping * offsetVelocity.y) * dt
        currentOffset.x += offsetVelocity.x * dt
        currentOffset.y += offsetVelocity.y * dt

        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.updatePaths(radius: self.currentRadius)
            let translate = CATransform3DMakeTranslation(self.currentOffset.x, self.currentOffset.y, 0)
            self.bubbleLayer.transform = translate
            self.highlightLayer.transform = translate
            self.pulseLayer.transform = translate
            let intensity = self.smoothedLevel
            self.bubbleLayer.shadowRadius = 12 + 20 * intensity
            self.bubbleLayer.shadowOpacity = Float(0.25 + (intensity * 0.55))
            self.highlightLayer.opacity = Float(self.state == .idle ? 0.18 : (0.3 + 0.35 * intensity))
            CATransaction.commit()
        }
    }

    private func radius(for level: CGFloat) -> CGFloat {
        let eased = pow(level, 0.45)
        return minRadius + (maxRadius - minRadius) * eased
    }

    private func updatePaths(radius: CGFloat) {
        let mainPath = circlePath(radius: radius)
        bubbleLayer.path = mainPath

        pulseLayer.path = circlePath(radius: radius * 1.35)

        let highlightRadius = radius * 0.75
        let highlightRect = CGRect(x: bounds.midX - highlightRadius,
                                   y: bounds.midY,
                                   width: highlightRadius * 2,
                                   height: highlightRadius)
        highlightLayer.path = CGPath(ellipseIn: highlightRect, transform: nil)
    }

    private func updateAppearance(animated: Bool) {
        let accent = NSColor.controlAccentColor
        let animation: CABasicAnimation? = animated ? {
            let anim = CABasicAnimation(keyPath: "fillColor")
            anim.duration = 0.2
            anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            return anim
        }() : nil

        switch state {
        case .idle:
            apply(color: accent.withAlphaComponent(0.35), border: accent.withAlphaComponent(0.6), glow: accent.withAlphaComponent(0.4), animation: animation)
        case .listening:
            apply(color: accent.withAlphaComponent(0.55), border: accent, glow: accent.withAlphaComponent(0.9), animation: animation)
        case .thinking:
            apply(color: accent.withAlphaComponent(0.45), border: accent.withAlphaComponent(0.9), glow: accent.withAlphaComponent(0.7), animation: animation)
        case .inserting:
            apply(color: NSColor.systemGreen.withAlphaComponent(0.55), border: NSColor.systemGreen, glow: NSColor.systemGreen.withAlphaComponent(0.8), animation: animation)
        case .error:
            apply(color: NSColor.systemRed.withAlphaComponent(0.5), border: NSColor.systemRed, glow: NSColor.systemRed.withAlphaComponent(0.8), animation: animation)
        }
    }

    private func apply(color: NSColor, border: NSColor, glow: NSColor, animation: CABasicAnimation?) {
        CATransaction.begin()
        CATransaction.setDisableActions(animation == nil)
        if let animation {
            animation.fromValue = bubbleLayer.presentation()?.fillColor
            bubbleLayer.add(animation, forKey: "fillColor")
        }
        bubbleLayer.fillColor = color.cgColor
        bubbleLayer.strokeColor = border.cgColor
        bubbleLayer.shadowColor = glow.cgColor
        pulseLayer.fillColor = glow.withAlphaComponent(0.18).cgColor
        highlightLayer.fillColor = NSColor.white.withAlphaComponent(0.25).cgColor
        CATransaction.commit()
    }

    private func circlePath(radius: CGFloat) -> CGPath {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let rect = CGRect(x: center.x - radius,
                          y: center.y - radius,
                          width: radius * 2,
                          height: radius * 2)
        return CGPath(ellipseIn: rect, transform: nil)
    }

    private func triggerPulse() {
        let now = CACurrentMediaTime()
        guard now - lastPulseTime > 0.22 else { return }
        lastPulseTime = now
        DispatchQueue.main.async {
            let start = self.circlePath(radius: self.currentRadius * 1.1)
            let end = self.circlePath(radius: self.currentRadius * 1.65)
            let pathAnim = CABasicAnimation(keyPath: "path")
            pathAnim.fromValue = start
            pathAnim.toValue = end
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 0.35
            opacity.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [pathAnim, opacity]
            group.duration = 0.45
            group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.1, 1)
            group.isRemovedOnCompletion = true
            self.pulseLayer.opacity = 0
            self.pulseLayer.add(group, forKey: "pulse")
        }
    }

    deinit {
        if let displayLink {
            CVDisplayLinkStop(displayLink)
        }
    }
}
