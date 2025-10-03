import SwiftUI
import AVFoundation

final class DictationOverlayViewModel: ObservableObject {
    @Published private(set) var state: DictationOverlayState = .idle
    @Published private(set) var audioLevel: CGFloat = 0
    @Published private(set) var smoothedAudioLevel: CGFloat = 0
    @Published private(set) var peakAudioLevel: CGFloat = 0
    @Published private(set) var levelHistory: [CGFloat]
    @Published private(set) var sessionDuration: TimeInterval = 0
    @Published private(set) var promptMessage: String?
    @Published private(set) var microphoneName: String
    @Published private(set) var hotkeyDisplay: String
    @Published private(set) var isThinking: Bool = false
    @Published private(set) var isErrorActive: Bool = false
    @Published private(set) var preferredFrameRate: Int = 30

    var isVisible: Bool { state != .idle }

    var visualIntensity: CGFloat {
        let combined = smoothedAudioLevel * 0.85 + ambientLevel * 0.15
        return max(0.05, min(combined, 1))
    }

    private static let historyCapacity = 120
    private static let smoothingFactor: CGFloat = 0.16
    private static let peakDecayPerSecond: CGFloat = 0.8
    private static let speakUpThreshold: CGFloat = 0.2

    private var ambientLevel: CGFloat = 0
    private var historyBuffer: [CGFloat]
    private var historyIndex: Int = 0
    private var lastPeakUpdate: CFTimeInterval = CACurrentMediaTime()
    private var listeningStart: CFTimeInterval?
    private var durationTimer: DispatchSourceTimer?
    private var promptWorkItem: DispatchWorkItem?
    private var errorResetWorkItem: DispatchWorkItem?

    init() {
        let defaults = PreferencesStore.shared.current
        self.levelHistory = Array(repeating: 0, count: Self.historyCapacity)
        self.historyBuffer = levelHistory
        self.microphoneName = DictationOverlayViewModel.resolveMicrophoneName(from: defaults.micSource)
        self.hotkeyDisplay = HotkeyFormatter.displayString(for: defaults.hotkey)
    }

    deinit {
        durationTimer?.cancel()
        promptWorkItem?.cancel()
        errorResetWorkItem?.cancel()
    }

    func updateState(_ newState: DictationOverlayState) {
        guard state != newState else { return }
        state = newState
        switch newState {
        case .idle:
            stopDurationTimer()
            sessionDuration = 0
            isThinking = false
            promptMessage = nil
            isErrorActive = false
            preferredFrameRate = 30
            cancelPrompt()
        case .listening:
            isThinking = false
            isErrorActive = false
            listeningStart = CACurrentMediaTime()
            startDurationTimer()
            schedulePromptEvaluation()
            preferredFrameRate = 60
        case .thinking:
            isThinking = true
            isErrorActive = false
            stopDurationTimer()
            preferredFrameRate = 48
            cancelPrompt()
        case .inserting:
            isThinking = false
            isErrorActive = false
            stopDurationTimer()
            preferredFrameRate = 45
            cancelPrompt()
        case .error:
            isErrorActive = true
            stopDurationTimer()
            scheduleErrorReset()
            preferredFrameRate = 60
            promptMessage = "Microphone issue detected"
        }
    }

    func handleAudioLevel(_ rawLevel: CGFloat) {
        let level = max(0, min(rawLevel, 1))
        audioLevel = level
        let factor = Self.smoothingFactor
        smoothedAudioLevel = smoothedAudioLevel * (1 - factor) + level * factor

        let now = CACurrentMediaTime()
        if smoothedAudioLevel > peakAudioLevel {
            peakAudioLevel = smoothedAudioLevel
            lastPeakUpdate = now
        } else {
            let decay = CGFloat(now - lastPeakUpdate) * Self.peakDecayPerSecond
            peakAudioLevel = max(smoothedAudioLevel, peakAudioLevel - decay)
        }

        ambientLevel = ambientLevel * 0.995 + smoothedAudioLevel * 0.005
        pushHistory(smoothedAudioLevel)

        if let message = promptMessage, message == Self.speakUpHint, smoothedAudioLevel > Self.speakUpThreshold {
            promptMessage = nil
        }
    }

    private func pushHistory(_ value: CGFloat) {
        historyBuffer[historyIndex] = value
        historyIndex = (historyIndex + 1) % Self.historyCapacity
        if historyIndex == 0 {
            levelHistory = historyBuffer
        } else {
            let head = Array(historyBuffer[historyIndex...])
            let tail = Array(historyBuffer[..<historyIndex])
            levelHistory = head + tail
        }
    }

    private func startDurationTimer() {
        stopDurationTimer()
        guard listeningStart != nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self, let start = self.listeningStart else { return }
            let elapsed = CACurrentMediaTime() - start
            self.sessionDuration = elapsed
        }
        timer.resume()
        durationTimer = timer
    }

    private func stopDurationTimer() {
        durationTimer?.cancel()
        durationTimer = nil
        listeningStart = nil
    }

    private func schedulePromptEvaluation() {
        cancelPrompt()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.state == .listening && self.smoothedAudioLevel < Self.speakUpThreshold {
                self.promptMessage = Self.speakUpHint
            }
        }
        promptWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func cancelPrompt() {
        promptWorkItem?.cancel()
        promptWorkItem = nil
        if promptMessage == Self.speakUpHint {
            promptMessage = nil
        }
    }

    private func scheduleErrorReset() {
        errorResetWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.isErrorActive = false
            if self?.promptMessage == "Microphone issue detected" {
                self?.promptMessage = nil
            }
        }
        errorResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    private static func resolveMicrophoneName(from stored: String) -> String {
        if !stored.isEmpty { return stored }
        if let device = AVCaptureDevice.default(for: .audio) {
            return device.localizedName
        }
        return "Default Microphone"
    }

    private static var speakUpHint: String { "Speak a little louder" }
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
                        preferredFrameRate: model.preferredFrameRate
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .transition(.opacity)

                    if model.isErrorActive {
                        Color.red.opacity(0.14)
                            .ignoresSafeArea()
                            .transition(.opacity)
                    }

                    OverlayFeatureStack(model: model)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()
        }
        .onAppear { lastState = model.state }
        .onChange(of: model.state) { current in
            if current == .listening, lastState != .listening {
                rippleTrigger &+= 1
            }
            lastState = current
        }
        .animation(.easeInOut(duration: 0.2), value: model.state)
    }
}

private struct OverlayFeatureStack: View {
    @ObservedObject var model: DictationOverlayViewModel

    var body: some View {
        ZStack {
            VStack {
                AudioMeterView(level: model.smoothedAudioLevel, peak: model.peakAudioLevel)
                    .padding(.top, 32)

                Spacer()

                AudioHistoryView(history: model.levelHistory)
                    .padding(.bottom, 160)

                StatusPanelView(
                    state: model.state,
                    sessionDuration: model.sessionDuration,
                    microphone: model.microphoneName,
                    prompt: model.promptMessage,
                    hotkey: model.hotkeyDisplay,
                    isThinking: model.isThinking
                )
                .padding(.bottom, 48)
            }
            .padding(.horizontal, 48)
        }
    }
}
