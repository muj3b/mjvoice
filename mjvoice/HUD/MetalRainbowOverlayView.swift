import SwiftUI
import MetalKit

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
        view.isOpaque = false
        view.layer?.isOpaque = false

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
            renderer.rippleStrength = 0.24
            renderer.rippleDuration = 1.1
        case .thinking, .inserting:
            renderer.rippleStrength = 0.16
            renderer.rippleDuration = 0.9
        case .error:
            renderer.rippleStrength = 0.3
            renderer.rippleDuration = 1.2
        case .idle:
            renderer.rippleStrength = 0.18
            renderer.rippleDuration = 1.0
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
