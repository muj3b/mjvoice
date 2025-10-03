import SwiftUI

final class DictationOverlayViewModel: ObservableObject {
    @Published private(set) var state: DictationOverlayState = .idle
    @Published private(set) var audioLevel: CGFloat = 0
    @Published private(set) var visualIntensity: CGFloat = 0

    var isVisible: Bool { state != .idle }

    private let smoothing: CGFloat = 0.18

    func updateState(_ newState: DictationOverlayState) {
        guard state != newState else { return }
        state = newState
        if newState == .idle {
            visualIntensity = 0
        }
    }

    func handleAudioLevel(_ rawLevel: CGFloat) {
        let level = max(0, min(rawLevel, 1))
        audioLevel = level
        visualIntensity = visualIntensity * (1 - smoothing) + level * smoothing
    }
}

struct DictationOverlayView: View {
    @ObservedObject var model: DictationOverlayViewModel
    @State private var rippleTrigger: Int = 0
    @State private var lastState: DictationOverlayState = .idle

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear
                if model.isVisible {
                    MetalRainbowOverlayView(
                        audioLevel: model.visualIntensity,
                        state: model.state,
                        rippleTrigger: rippleTrigger,
                        preferredFrameRate: preferredFrameRate(for: model.state)
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .transition(.opacity)
                }
            }
            .ignoresSafeArea()
        }
        .onAppear { lastState = model.state }
        .onChange(of: model.state) { current in
            if current == .listening, lastState != .listening {
                rippleTrigger &+= 1
            } else if current == .error, lastState != .error {
                rippleTrigger &+= 1
            }
            lastState = current
        }
        .animation(.easeInOut(duration: 0.18), value: model.state)
    }

    private func preferredFrameRate(for state: DictationOverlayState) -> Int {
        switch state {
        case .listening: return 60
        case .thinking: return 48
        case .error: return 60
        case .inserting: return 50
        case .idle: return 30
        }
    }
}
