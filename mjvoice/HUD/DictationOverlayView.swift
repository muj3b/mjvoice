import SwiftUI

final class DictationOverlayViewModel: ObservableObject {
    @Published var state: DictationOverlayState = .idle
    @Published var audioLevel: CGFloat = 0

    var isVisible: Bool { state != .idle }
}

struct DictationOverlayView: View {
    @ObservedObject var model: DictationOverlayViewModel
    private let edgeInset: CGFloat = 24

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                ZStack {
                    Color.clear
                    if model.isVisible {
                        borderGlow(in: proxy.size, phase: phase)
                            .transition(.opacity)
                    }
                }
                .ignoresSafeArea()
            }
            .animation(.easeInOut(duration: 0.25), value: model.state)
        }
    }

    private func borderGlow(in size: CGSize, phase: TimeInterval) -> some View {
        let hueShift = phase * 0.45
        let colors: [Color] = (0..<6).map { index in
            let hue = (sin(hueShift + Double(index) * 0.9) + 1) / 2
            return Color(hue: hue, saturation: 0.85, brightness: 0.95)
        }
        let gradient = AngularGradient(gradient: Gradient(colors: colors), center: .center)
        let lineWidth = CGFloat(10 + model.audioLevel * 18)
        let blurRadius = CGFloat(28 + model.audioLevel * 36)
        let inset = edgeInset + lineWidth / 2

        return Rectangle()
            .inset(by: inset)
            .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .blur(radius: blurRadius)
            .overlay(
                Rectangle()
                    .inset(by: inset)
                    .stroke(Color.white.opacity(0.18 + model.audioLevel * 0.28), lineWidth: max(2, lineWidth * 0.35))
            )
            .blendMode(.screen)
            .frame(width: size.width, height: size.height)
    }
}
