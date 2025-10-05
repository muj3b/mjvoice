import AppKit
import SwiftUI

final class DictationButtonWindow: NSPanel {
    private let hostingController: NSHostingController<DictationButtonView>
    private var currentScreen: NSScreen?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        hostingController = NSHostingController(rootView: DictationButtonView())
        super.init(contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        ignoresMouseEvents = false // this window captures clicks

        contentView = hostingController.view
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    convenience init() {
        self.init(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
    }

    func present(on screen: NSScreen) {
        currentScreen = screen
        let size = CGSize(width: 96, height: 96)
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.minY + 64
        let frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        setFrame(frame, display: true)
        hostingController.view.frame = NSRect(origin: .zero, size: frame.size)
        if !isVisible { orderFrontRegardless() }
    }

    func hide() {
        orderOut(nil)
    }
}

private struct DictationButtonView: View {
    @State private var isActive = false

    var body: some View {
        Button(action: togglePTT) {
            Image(systemName: isActive ? "pause.fill" : "mic.fill")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 6)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(1.0)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                // Slight press-in effect
            }
        }.onEnded { _ in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                // Return to normal size
            }
        })
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isActive)
        .onReceive(NotificationCenter.default.publisher(for: .pttStart)) { _ in
            isActive = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .pttStop)) { _ in
            isActive = false
        }
        .accessibilityLabel(isActive ? "Stop dictation" : "Start dictation")
        .accessibilityAddTraits(.isButton)
    }

    private func togglePTT() {
        if isActive {
            NotificationCenter.default.post(name: .pttStop, object: nil)
        } else {
            NotificationCenter.default.post(name: .pttStart, object: nil)
        }
    }
}
