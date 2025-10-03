import SwiftUI
import MetalKit
import AppKit

struct MetalRainbowOverlayView: NSViewRepresentable {
    var audioLevel: CGFloat
    var state: DictationOverlayState
    var rippleTrigger: Int
    var preferredFrameRate: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.wantsLayer = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.framebufferOnly = false
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor

        do {
            let renderer = try MetalRainbowRenderer(mtkView: view)
            renderer.audioLevel = Float(audioLevel)
            context.coordinator.renderer = renderer
        } catch {
            context.coordinator.error = error
        }
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        renderer.audioLevel = Float(audioLevel)
        renderer.updateDrawableSize(view.drawableSize)
        if view.preferredFramesPerSecond != preferredFrameRate {
            view.preferredFramesPerSecond = preferredFrameRate
        }

        switch state {
        case .listening:
            renderer.rippleStrength = 0.18
            renderer.rippleDuration = 1.15
        case .thinking, .inserting:
            renderer.rippleStrength = 0.12
            renderer.rippleDuration = 0.95
        case .error:
            renderer.rippleStrength = 0.26
            renderer.rippleDuration = 1.25
        case .idle:
            renderer.rippleStrength = 0.14
            renderer.rippleDuration = 1.05
        }

        if context.coordinator.lastRippleTrigger != rippleTrigger {
            renderer.triggerRipple()
            context.coordinator.lastRippleTrigger = rippleTrigger
        }
    }

    final class Coordinator {
        var renderer: MetalRainbowRenderer?
        var error: Error?
        var lastRippleTrigger: Int = 0
    }
}
