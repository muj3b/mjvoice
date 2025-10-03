import SwiftUI
import AppKit

struct PrimaryCTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background(Color.accentColor.opacity(configuration.isPressed ? 0.6 : 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            )
            .foregroundColor(.accentColor)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0 : 0.15), radius: 4, x: 0, y: 2)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func cardBackground() -> some View {
        self.modifier(CardBackground())
    }
}
