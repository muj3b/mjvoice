import SwiftUI
import AppKit

final class DictationOverlayViewModel: ObservableObject {
    @Published var state: DictationOverlayState = .idle
}

struct DictationOverlayView: View {
    @ObservedObject var model: DictationOverlayViewModel

    var body: some View {
        SiriEdgeContainer(state: model.state)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .background(Color.clear)
    }
}

private struct SiriEdgeContainer: NSViewRepresentable {
    var state: DictationOverlayState

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SiriEdgeMetalView {
        let view = SiriEdgeMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ nsView: SiriEdgeMetalView, context: Context) {
        if let superview = nsView.superview {
            nsView.frame = superview.bounds
        }
        if state == .idle {
            nsView.deactivate()
        } else {
            if !nsView.isActive {
                nsView.activate()
            }
            if state == .listening && context.coordinator.lastState != .listening {
                nsView.triggerRipple()
            }
            if state == .error && context.coordinator.lastState != .error {
                nsView.triggerRipple(intensity: 1.0)
            }
        }
        context.coordinator.lastState = state
        if let window = nsView.window, let screen = window.screen {
            let radius = SiriEdgeMetalView.cornerRadius(for: screen)
            nsView.updateCornerRadius(CGFloat(radius))
        }
    }

    final class Coordinator {
        var lastState: DictationOverlayState = .idle
    }
}

