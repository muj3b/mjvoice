import SwiftUI
import AppKit

final class HUDController {
    static let shared = HUDController()

    private var window: NSPanel?
    private var hosting: NSHostingView<HUDView>?

    private init() {
        NotificationCenter.default.addObserver(self, selector: #selector(handlePTTStart), name: .pttStart, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePTTStop), name: .pttStop, object: nil)
    }

    @objc private func handlePTTStart() {
        DispatchQueue.main.async { self.showHUD() }
    }

    @objc private func handlePTTStop() {
        DispatchQueue.main.async { self.dismissHUD(animated: true) }
    }

    private func makeWindowIfNeeded() {
        guard window == nil else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        window = panel
    }

    private func centerInScreen(_ win: NSWindow) {
        if let screen = NSScreen.main {
            let rect = screen.visibleFrame
            let size = win.frame.size
            let origin = NSPoint(x: rect.midX - size.width/2, y: rect.midY - size.height/2)
            win.setFrame(NSRect(origin: origin, size: size), display: true)
        } else {
            win.center()
        }
    }

    private func showHUD() {
        makeWindowIfNeeded()
        guard let panel = window else { return }

        let view = HUDView()
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 180)
        panel.contentView = host
        hosting = host

        centerInScreen(panel)
        panel.orderFrontRegardless()

        // Kick off entrance animation
        view.appear()
    }

    private func dismissHUD(animated: Bool) {
        guard let panel = window, let host = hosting else { return }
        let hud = host.rootView
        hud.disappear { [weak self] in
            guard let self = self else { return }
            panel.orderOut(nil)
            self.hosting = nil
            self.window = nil
        }
    }
}

private final class HUDAnimator: ObservableObject {
    @Published var visible: Bool = false
    @Published var scale: CGFloat = 0.92
    @Published var opacity: Double = 0.0
    @Published var blur: CGFloat = 8
}

struct HUDView: View {
    @StateObject private var anim = HUDAnimator()

    fileprivate func appear() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0.2)) {
            anim.visible = true
            anim.scale = 1.0
            anim.opacity = 1.0
            anim.blur = 0
        }
    }

    fileprivate func disappear(completion: @escaping () -> Void) {
        withAnimation(.easeIn(duration: 0.22)) {
            anim.blur = 6
        }
        withAnimation(.easeIn(duration: 0.28)) {
            anim.opacity = 0.0
        }
        withAnimation(.easeIn(duration: 0.35)) {
            anim.scale = 0.65 // zoom out into the abyss
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: completion)
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )

            VStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.accent)
                Text("Listening…")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Hold to dictate. Release to insert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .frame(width: 320, height: 180)
        .scaleEffect(anim.scale)
        .opacity(anim.opacity)
        .blur(radius: anim.blur)
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 12)
        .onAppear { /* initial state is set in animator */ }
    }
}

extension View {
    func disappear(completion: @escaping () -> Void) {
        if let hud = self as? HUDView {
            hud.disappear(completion: completion)
        } else {
            completion()
        }
    }
}

// VisualEffectView is needed for the HUDView background

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

extension Notification.Name {
    static let pttStart = Notification.Name("pttStart")
    static let pttStop = Notification.Name("pttStop")
}
