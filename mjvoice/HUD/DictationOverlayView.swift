import SwiftUI

final class DictationOverlayViewModel: ObservableObject {
    @Published var state: DictationOverlayState = .idle
    @Published var audioLevel: CGFloat = 0

    var isVisible: Bool { state != .idle }
}

struct DictationOverlayView: View {
    @ObservedObject var model: DictationOverlayViewModel

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear
                if model.isVisible {
                    DictationGlowBorder(size: proxy.size, audioLevel: model.audioLevel)
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.2), value: model.state)
    }
}

private struct DictationGlowBorder: View {
    let size: CGSize
    let audioLevel: CGFloat

    @State private var gradientStops: [Gradient.Stop] = Self.generateGradientStops()
    @State private var refreshTask: Task<Void, Never>? = nil

    private var intensity: CGFloat { max(0, min(audioLevel, 1)) }
    private var baseInset: CGFloat { Self.baseInset(for: size) }

    var body: some View {
        ZStack {
            glowLayer(baseWidth: 4, widthGain: 11, baseBlur: 10, blurGain: 22, insetOffset: 0)
            glowLayer(baseWidth: 6, widthGain: 12, baseBlur: 18, blurGain: 34, insetOffset: 8)
            highlightLayer(insetOffset: 6)
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: startRefreshing)
        .onDisappear(perform: stopRefreshing)
    }

    private func glowLayer(baseWidth: CGFloat,
                           widthGain: CGFloat,
                           baseBlur: CGFloat,
                           blurGain: CGFloat,
                           insetOffset: CGFloat) -> some View {
        let lineWidth = baseWidth + intensity * widthGain
        let blurRadius = baseBlur + intensity * blurGain
        let inset = baseInset + insetOffset + lineWidth / 2
        return Rectangle()
            .inset(by: inset)
            .strokeBorder(
                AngularGradient(gradient: Gradient(stops: gradientStops), center: .center),
                lineWidth: lineWidth
            )
            .frame(width: size.width, height: size.height)
            .blur(radius: blurRadius)
            .opacity(0.78)
    }

    private func highlightLayer(insetOffset: CGFloat) -> some View {
        let lineWidth = max(1.6, 2.8 + intensity * 4)
        let inset = baseInset + insetOffset

        return Rectangle()
            .inset(by: inset + lineWidth / 2)
            .stroke(Color.white.opacity(0.08 + intensity * 0.2), lineWidth: lineWidth)
            .frame(width: size.width, height: size.height)
            .blur(radius: lineWidth * 2.6)
            .blendMode(.screen)
    }

    private func startRefreshing() {
        guard refreshTask == nil else { return }
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                let nextStops = Self.generateGradientStops()
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        gradientStops = nextStops
                    }
                }
            }
        }
    }

    private func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private static func baseInset(for size: CGSize) -> CGFloat {
        max(0, min(size.width, size.height) * 0.0025)
    }

    private static func generateGradientStops() -> [Gradient.Stop] {
        [
            Gradient.Stop(color: Color(hex: "BC82F3"), location: Double.random(in: 0...1)),
            Gradient.Stop(color: Color(hex: "F5B9EA"), location: Double.random(in: 0...1)),
            Gradient.Stop(color: Color(hex: "8D9FFF"), location: Double.random(in: 0...1)),
            Gradient.Stop(color: Color(hex: "FF6778"), location: Double.random(in: 0...1)),
            Gradient.Stop(color: Color(hex: "FFBA71"), location: Double.random(in: 0...1)),
            Gradient.Stop(color: Color(hex: "C686FF"), location: Double.random(in: 0...1))
        ].sorted { $0.location < $1.location }
    }
}

private extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        _ = scanner.scanString("#")

        var hexNumber: UInt64 = 0
        scanner.scanHexInt64(&hexNumber)

        let r = Double((hexNumber & 0xff0000) >> 16) / 255
        let g = Double((hexNumber & 0x00ff00) >> 8) / 255
        let b = Double(hexNumber & 0x0000ff) / 255

        self.init(red: r, green: g, blue: b)
    }
}
