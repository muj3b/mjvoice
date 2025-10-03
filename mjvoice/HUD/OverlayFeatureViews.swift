import SwiftUI

struct AudioMeterView: View {
    let level: CGFloat
    let peak: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                Capsule()
                    .fill(LinearGradient(colors: [Color.blue.opacity(0.4), Color.purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(2, level * width))
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2)
                    .offset(x: max(0, min(peak, 1) * width - 1))
            }
        }
        .frame(height: 10)
        .padding(.horizontal, 120)
        .accessibilityHidden(true)
    }
}

struct AudioHistoryView: View {
    let history: [CGFloat]

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                guard history.count > 1 else { return }
                var path = Path()
                let step = size.width / CGFloat(history.count - 1)
                for (index, sample) in history.enumerated() {
                    let x = CGFloat(index) * step
                    let y = size.height - CGFloat(sample) * size.height
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(path, with: .color(Color.white.opacity(0.45)), lineWidth: 2)
            }
        }
        .frame(height: 64)
        .padding(.horizontal, 160)
        .accessibilityHidden(true)
    }
}

struct StatusPanelView: View {
    let state: DictationOverlayState
    let sessionDuration: TimeInterval
    let microphone: String
    let prompt: String?
    let hotkey: String
    let isThinking: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text(stateTitle)
                    .font(.system(size: 22, weight: .semibold))
                if isThinking {
                    ThinkingIndicatorView()
                        .frame(width: 22, height: 22)
                }
                Spacer()
                if let formatted = timerText {
                    Text(formatted)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            }
            .foregroundStyle(Color.white)

            if let message = prompt {
                Text(message)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.orange.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Label(microphoneLabel, systemImage: "mic.fill")
                    .foregroundStyle(Color.white.opacity(0.85))
                    .labelStyle(.titleAndIcon)
                Spacer()
                if !hotkey.isEmpty {
                    Label("Hotkey: \(hotkey)", systemImage: "keyboard")
                        .foregroundStyle(Color.white.opacity(0.7))
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(.system(size: 14, weight: .regular))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 60)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(panelAccessibilityLabel)
    }

    private var stateTitle: String {
        switch state {
        case .idle: return "Idle"
        case .listening: return "Listening"
        case .thinking: return "Processing"
        case .inserting: return "Inserting"
        case .error: return "Error"
        }
    }

    private var timerText: String? {
        guard state == .listening else { return nil }
        let seconds = Int(sessionDuration)
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }

    private var microphoneLabel: String {
        "Mic: \(microphone)"
    }

    private var panelAccessibilityLabel: String {
        var parts: [String] = [stateTitle]
        if let timer = timerText { parts.append("Timer \(timer)") }
        parts.append(microphoneLabel)
        if let message = prompt { parts.append(message) }
        if !hotkey.isEmpty { parts.append("Hotkey \(hotkey)") }
        return parts.joined(separator: ", ")
    }
}

struct ThinkingIndicatorView: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0.25, to: 1)
            .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(rotation))
            .onAppear { animate() }
            .onDisappear { reset() }
    }

    private func animate() {
        withAnimation(Animation.linear(duration: 1).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }

    private func reset() {
        rotation = 0
    }
}
