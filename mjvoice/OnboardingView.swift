import SwiftUI
import AppKit

struct OnboardingView: View {
    @State private var currentStep = 0
    @State private var isDownloadingModel = false
    @State private var downloadProgress: Double = 0.0
    @State private var modelDownloaded = false

    let steps = [
        OnboardingStep(
            title: "Welcome to mjvoice",
            subtitle: "Your AI-powered dictation app for macOS",
            content: "mjvoice brings lightning-fast, privacy-first dictation with AI writing assistance. Dictate anywhere on your Mac with system-wide functionality.",
            imageName: "mic.fill",
            features: []
        ),
        OnboardingStep(
            title: "Key Features",
            subtitle: "Everything you need for seamless dictation",
            content: "",
            imageName: "star.fill",
            features: [
                "Push-to-Talk with global hotkey (default: ⌘⌥Space)",
                "Offline ASR with Whisper models (Tiny/Base/Small)",
                "AI formatting: smart punctuation, capitalization, filler removal",
                "Liquid glass UI with smooth animations",
                "Secure: no data leaves your device when offline",
                "System-wide: works in any app, even password fields auto-pause"
            ]
        ),
        OnboardingStep(
            title: "Keyboard Shortcuts",
            subtitle: "Master the controls",
            content: "",
            imageName: "keyboard",
            features: [
                "⌘⌥Space: Start/stop dictation (configurable)",
                "Hold hotkey: Press-and-hold mode",
                "Double-tap hotkey: Toggle mode",
                "Settings: Click menubar icon → Preferences",
                "Rewind: Right-click menubar icon → Rewind last 30s"
            ]
        ),
        OnboardingStep(
            title: "Choose Your ASR Model",
            subtitle: "Select the speech recognition engine",
            content: "mjvoice supports multiple offline ASR models. Choose based on your needs:",
            imageName: "waveform",
            features: [
                "Whisper (OpenAI): Highly accurate, supports many languages, larger models for better quality.",
                "Fluid Audio: Optimized for real-time performance, lighter on resources, good for quick dictation."
            ]
        ),
        OnboardingStep(
            title: "Download Models",
            subtitle: "Get your chosen models",
            content: "Download the ASR and noise suppression models. Models are stored locally for offline use.",
            imageName: "arrow.down.circle.fill",
            features: [
                "ASR Model: Based on your choice (Whisper or Fluid)",
                "Noise Model: dtln-rs for best quality",
                "Models download automatically on first use"
            ]
        ),
        OnboardingStep(
            title: "Customize Your Experience",
            subtitle: "Tailor mjvoice to your workflow",
            content: "Set your preferred hotkey, dictation mode, and AI writing style. Per-app presets let you adapt behavior for different contexts.",
            imageName: "gear",
            features: [
                "Choose dictation mode: Streaming, Instant, or Notes",
                "Select AI tone: Neutral, Professional, Friendly",
                "Configure push-to-talk: Press-and-hold, Latch, or Toggle",
                "Import custom vocabulary from CSV",
                "Set per-app behavior presets",
                "Customize grammar prompts per app"
            ]
        )
    ]

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
                    Image(systemName: steps[currentStep].imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundColor(.accentColor)

                    Text(steps[currentStep].title)
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(steps[currentStep].subtitle)
                        .font(.title2)
                        .foregroundColor(.secondary)

                    if !steps[currentStep].content.isEmpty {
                        Text(steps[currentStep].content)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }

                    if !steps[currentStep].features.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(steps[currentStep].features, id: \.self) { feature in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .frame(width: 20)
                                    Text(feature)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    if currentStep == 4 { // Download models step
                        VStack(spacing: 16) {
                            if modelDownloaded {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Model downloaded successfully!")
                                }
                            } else if isDownloadingModel {
                                VStack {
                                    ProgressView(value: downloadProgress, total: 1.0)
                                        .progressViewStyle(LinearProgressViewStyle())
                                    Text("Downloading... \(Int(downloadProgress * 100))%")
                                        .font(.caption)
                                }
                            } else {
                                Button("Download Small Model (244MB)") {
                                    downloadModel()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
                .padding(.horizontal, 40)
                .frame(maxWidth: 600)

                Spacer()

                HStack {
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation(.spring()) {
                                currentStep -= 1
                            }
                        }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        ForEach(0..<steps.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }

                    Spacer()

                    if currentStep < steps.count - 1 {
                        Button("Next") {
                            withAnimation(.spring()) {
                                currentStep += 1
                            }
                        }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("Get Started") {
                            completeOnboarding()
                        }
                        .keyboardShortcut(.return, modifiers: [])
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .frame(width: 800, height: 600)
    }

    private func downloadModel() {
        guard !isDownloadingModel else { return }
        isDownloadingModel = true
        downloadProgress = 0.0

        let prefs = PreferencesStore.shared.current
        ModelManager.shared.downloadDefaultModel(for: prefs.asrModel, size: prefs.modelSize) { progress in
            DispatchQueue.main.async {
                self.downloadProgress = progress * 0.5
            }
        } completion: { result in
            DispatchQueue.main.async {
                self.isDownloadingModel = false
                switch result {
                case .success:
                    self.downloadNoiseModelIfNeeded()
                case .failure(let error):
                    self.modelDownloaded = false
                    NSApp.presentError(error)
                    Task { @MainActor in
                        EventLogStore.shared.record(type: .modelDownloadFailed, message: "ASR model download failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func downloadNoiseModelIfNeeded() {
        let prefs = PreferencesStore.shared.current
        ModelManager.shared.downloadDefaultNoiseModel(prefs.noiseModel) { progress in
            DispatchQueue.main.async {
                self.downloadProgress = 0.5 + progress / 2
            }
        } completion: { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.modelDownloaded = true
                    Task { @MainActor in
                        EventLogStore.shared.record(type: .modelDownload, message: "Noise model ready")
                    }
                case .failure(let error):
                    NSApp.presentError(error)
                    Task { @MainActor in
                        EventLogStore.shared.record(type: .modelDownloadFailed, message: "Noise model failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func completeOnboarding() {
        PreferencesStore.shared.update { $0.hasCompletedOnboarding = true }
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.dismissOnboarding()
        } else {
            NSApp.keyWindow?.close()
        }
    }
}

struct OnboardingStep {
    let title: String
    let subtitle: String
    let content: String
    let imageName: String
    let features: [String]
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
