import SwiftUI

struct PreferencesView: View {
    @State private var prefs = PreferencesStore.shared.current
    @State private var recordingHotkey = false
    @State private var hotkeyError: String? = nil
    @State private var asrDownloadProgress: Double = 0
    @State private var noiseDownloadProgress: Double = 0
    @State private var isDownloadingASR = false
    @State private var isDownloadingNoise = false
    @State private var installedASR: [InstalledModelRecord] = []
    @State private var installedNoise: [InstalledModelRecord] = []
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var isInstallingFluidRuntime = false
    @State private var fluidInstallStatus: String? = nil

    private let modelManager = ModelManager.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                header
                generalCard
                modelCard
                aiCard
                appearanceCard
            }
            .padding(32)
        }
        .frame(minWidth: 560)
        .background(LinearGradient(colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .alert(alertMessage ?? "", isPresented: $showAlert) { Button("OK", role: .cancel) { } }
        .onAppear(perform: refreshModels)
        .onReceive(NotificationCenter.default.publisher(for: ModelManager.modelsDidChangeNotification)) { _ in
            refreshModels()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("mjvoice Preferences")
                .font(.system(size: 22, weight: .semibold))
            Text("Adjust dictation behaviour, engines, and output polishing.")
                .font(.system(size: 13))
                .foregroundStyle(Color.secondary)
        }
    }

    private var generalCard: some View {
        PreferenceCard(title: "General", symbol: "slider.horizontal.3") {
            VStack(spacing: 18) {
                hotkeyRow
                ToggleRow(title: "Offline mode", subtitle: "Force on-device recognition for sensitive material.", isOn: Binding(
                    get: { prefs.offlineMode },
                    set: { new in update { $0.offlineMode = new } }
                ))
                PickerRow(title: "Default mode", selection: Binding(
                    get: { prefs.defaultMode },
                    set: { new in update { $0.defaultMode = new } }
                ), items: dictationModeOptions)
                PickerRow(title: "Hotkey style", selection: Binding(
                    get: { prefs.pttMode },
                    set: { new in
                        update { $0.pttMode = new }
                        GlobalHotkeyManager.shared.configure(mode: new)
                    }
                ), items: pttModeOptions)
                TextFieldRow(title: "Language", text: Binding(
                    get: { prefs.language },
                    set: { new in update { $0.language = new } }
                ))
                ToggleRow(title: "Auto capitalize", isOn: Binding(
                    get: { prefs.autoCapitalize },
                    set: { new in update { $0.autoCapitalize = new } }
                ))
                ToggleRow(title: "Remove filler words", isOn: Binding(
                    get: { prefs.removeFiller },
                    set: { new in update { $0.removeFiller = new } }
                ))
            }
        }
    }

    private var modelCard: some View {
        PreferenceCard(title: "Speech models", symbol: "waveform") {
            VStack(alignment: .leading, spacing: 20) {
                PickerRow(title: "ASR engine", selection: Binding(
                    get: { prefs.selectedASRModelID ?? modelIdentifierDefault(for: prefs) },
                    set: { new in update { $0.selectedASRModelID = new } }
                ), items: defaultAndInstalledASR())

                if isDownloadingASR {
                    ProgressView(value: asrDownloadProgress) { Text("Downloading ASR model…") }
                }

                ButtonRow(title: "Download \(prefs.asrModel == .whisper ? "Whisper" : "Fluid") \(prefs.modelSize.rawValue.capitalized) model") {
                    startASRDownload()
                }

                ButtonRow(title: "Install Fluid runtime", subtitle: fluidInstallStatus) {
                    installFluidRuntime()
                }
                .disabled(isInstallingFluidRuntime)

                if !installedASR.isEmpty {
                    ModelList(title: "Installed ASR models", records: installedASR, onReveal: revealModel, onDelete: deleteModel)
                }

                Divider().padding(.vertical, 4)

                PickerRow(title: "Noise suppression", selection: Binding(
                    get: { prefs.selectedNoiseModelID ?? defaultNoiseIdentifier(for: prefs.noiseModel) },
                    set: { new in update { $0.selectedNoiseModelID = new } }
                ), items: defaultAndInstalledNoise())

                if isDownloadingNoise {
                    ProgressView(value: noiseDownloadProgress) { Text("Downloading noise model…") }
                }

                ButtonRow(title: "Download \(prefs.noiseModel == .dtln_rs ? "dtln-rs" : "RNNoise") model") {
                    startNoiseDownload()
                }

                if !installedNoise.isEmpty {
                    ModelList(title: "Installed noise models", records: installedNoise, onReveal: revealModel, onDelete: deleteModel)
                }
            }
        }
    }

    private var aiCard: some View {
        PreferenceCard(title: "AI output", symbol: "sparkles") {
            VStack(spacing: 16) {
                ToggleRow(title: "Grammar fixer", subtitle: "Uses your prompt after each transcript to tidy phrasing.", isOn: Binding(
                    get: { prefs.enableAIGrammar },
                    set: { new in update { $0.enableAIGrammar = new } }
                ))
                TextFieldRow(title: "Prompt", text: Binding(
                    get: { prefs.defaultGrammarPrompt },
                    set: { new in update { $0.defaultGrammarPrompt = new } }
                ))
            }
        }
    }

    private var appearanceCard: some View {
        PreferenceCard(title: "Appearance", symbol: "paintpalette") {
            PickerRow(title: "Theme", selection: Binding(
                get: { prefs.theme },
                set: { new in update { $0.theme = new } }
            ), items: [("auto", "Auto"), ("light", "Light"), ("dark", "Dark")])
        }
    }

    // MARK: - Rows

    private var hotkeyRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hotkey")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if recordingHotkey {
                    HotkeyRecorder(onRecord: { newHotkey in
                        recordingHotkey = false
                        if let newHotkey {
                            update { $0.hotkey = newHotkey }
                            GlobalHotkeyManager.shared.registerDefaultHotkey()
                            hotkeyError = nil
                        } else {
                            hotkeyError = "Invalid hotkey or already in use"
                        }
                    })
                } else {
                    Text(displayHotkey(prefs.hotkey))
                        .font(.system(size: 13, weight: .medium))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                    Button("Change") {
                        recordingHotkey = true
                        hotkeyError = nil
                    }
                }
            }
            if let error = hotkeyError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }
        }
    }

    // MARK: - Helpers

    private func update(_ mutate: (inout UserPreferences) -> Void) {
        PreferencesStore.shared.update { prefs in
            mutate(&prefs)
            self.prefs = prefs
        }
    }

    private func refreshModels() {
        installedASR = modelManager.installedModels(kind: .asr)
        installedNoise = modelManager.installedModels(kind: .noise)
        if let id = prefs.selectedASRModelID,
           !installedASR.contains(where: { $0.descriptor.id == id }) {
            update { $0.selectedASRModelID = nil }
        }
        if let id = prefs.selectedNoiseModelID,
           !installedNoise.contains(where: { $0.descriptor.id == id }) {
            update { $0.selectedNoiseModelID = nil }
        }
    }

    private func startASRDownload() {
        guard !isDownloadingASR else { return }
        isDownloadingASR = true
        asrDownloadProgress = 0
        modelManager.downloadDefaultModel(for: prefs.asrModel, size: prefs.modelSize) { progress in
            asrDownloadProgress = progress
        } completion: { result in
            isDownloadingASR = false
            switch result {
            case .success(let url):
                alert("Model downloaded to \(url.lastPathComponent)")
                refreshModels()
                EventLogStore.shared.record(type: .modelDownload, message: "ASR model ready: \(url.lastPathComponent)")
            case .failure(let error):
                alert(error.localizedDescription)
                EventLogStore.shared.record(type: .modelDownloadFailed, message: "ASR download failed: \(error.localizedDescription)")
            }
        }
    }

    private func startNoiseDownload() {
        guard !isDownloadingNoise else { return }
        isDownloadingNoise = true
        noiseDownloadProgress = 0
        modelManager.downloadDefaultNoiseModel(prefs.noiseModel) { progress in
            noiseDownloadProgress = progress
        } completion: { result in
            isDownloadingNoise = false
            switch result {
            case .success(let url):
                alert("Noise model saved to \(url.lastPathComponent)")
                refreshModels()
                EventLogStore.shared.record(type: .modelDownload, message: "Noise model ready: \(url.lastPathComponent)")
            case .failure(let error):
                alert(error.localizedDescription)
                EventLogStore.shared.record(type: .modelDownloadFailed, message: "Noise download failed: \(error.localizedDescription)")
            }
        }
    }

    private func installFluidRuntime() {
        guard !isInstallingFluidRuntime else { return }
        isInstallingFluidRuntime = true
        fluidInstallStatus = "Starting…"
        Task {
            do {
                let url = try await DictationRuntimeHelper.installFluidRuntime { message in
                    Task { @MainActor in
                        if isInstallingFluidRuntime {
                            fluidInstallStatus = message
                        }
                    }
                }
                await MainActor.run {
                    isInstallingFluidRuntime = false
                    fluidInstallStatus = "Installed at \(url.path)"
                    alert("Fluid runtime installed at \(url.path)")
                }
            } catch {
                await MainActor.run {
                    isInstallingFluidRuntime = false
                    fluidInstallStatus = ""
                    alert("Fluid runtime install failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func revealModel(_ record: InstalledModelRecord) {
        if let url = modelManager.location(for: record.descriptor.id) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func deleteModel(_ record: InstalledModelRecord) {
        modelManager.deleteModel(id: record.descriptor.id)
        if prefs.selectedASRModelID == record.descriptor.id {
            update { $0.selectedASRModelID = nil }
        }
        if prefs.selectedNoiseModelID == record.descriptor.id {
            update { $0.selectedNoiseModelID = nil }
        }
        refreshModels()
    }

    private func alert(_ message: String) {
        alertMessage = message
        showAlert = true
    }

    private func defaultAndInstalledASR() -> [(String, String)] {
        var items: [(String, String)] = [(modelIdentifierDefault(for: prefs), defaultModelDisplay(for: prefs))]
        for record in installedASR {
            items.append((record.descriptor.id, "\(record.descriptor.name) — \(record.descriptor.provider)"))
        }
        return items
    }

    private func defaultAndInstalledNoise() -> [(String, String)] {
        var items: [(String, String)] = [(defaultNoiseIdentifier(for: prefs.noiseModel), defaultNoiseDisplay(for: prefs))]
        for record in installedNoise {
            items.append((record.descriptor.id, record.descriptor.name))
        }
        return items
    }

    private var supportedLanguages: [(String, String)] {
        ["en", "fr", "de", "es", "it", "ja", "hi"].map { ($0, $0.uppercased()) }
    }

    private var dictationModeOptions: [(DictationMode, String)] {
        [(.streaming, "Streaming"), (.instant, "Instant"), (.notes, "Notes")]
    }

    private var pttModeOptions: [(PTTMode, String)] {
        [(.pressHold, "Press and hold"), (.latch, "Latch"), (.toggle, "Toggle")]
    }

    private func label(for mode: PTTMode) -> String {
        switch mode {
        case .pressHold: return "Press and hold"
        case .latch: return "Latch"
        case .toggle: return "Toggle"
        }
    }

    private func modelIdentifierDefault(for prefs: UserPreferences) -> String {
        switch prefs.asrModel {
        case .whisper:
            return "whisper-\(prefs.modelSize.rawValue)"
        case .fluid:
            switch prefs.modelSize {
            case .tiny: return "fluid-light"
            case .base: return "fluid-pro"
            case .small: return "fluid-advanced"
            }
        }
    }

    private func defaultModelDisplay(for prefs: UserPreferences) -> String {
        switch prefs.asrModel {
        case .whisper:
            return "Whisper \(prefs.modelSize.rawValue.capitalized) (default)"
        case .fluid:
            return "Fluid \(prefs.modelSize.rawValue.capitalized) (default)"
        }
    }

    private func defaultNoiseDisplay(for prefs: UserPreferences) -> String {
        switch prefs.noiseModel {
        case .dtln_rs: return "dtln-rs (default)"
        case .rnnoise: return "RNNoise (default)"
        }
    }

    private func defaultNoiseIdentifier(for noise: NoiseModel) -> String {
        switch noise {
        case .dtln_rs: return "dtln-rs"
        case .rnnoise: return "rnnoise"
        }
    }

    private func displayHotkey(_ hotkey: Hotkey) -> String {
        let mods = hotkey.modifiers.map { $0.capitalized }.joined(separator: "+")
        if mods.isEmpty {
            return hotkey.key.uppercased()
        } else {
            return mods + "+" + hotkey.key.uppercased()
        }
    }
}

private struct PreferenceCard<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .background(RoundedRectangle(cornerRadius: 24).fill(Color.black.opacity(0.1)))
    }
}

private struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    init(title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: interceptBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                    }
                }
            }
        }
    }

    private var interceptBinding: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { newValue in
                SoundEffects.shared.play(newValue ? .toggleOn : .toggleOff)
                isOn = newValue
            }
        )
    }
}

private struct PickerRow<Selection: Hashable>: View {
    let title: String
    @Binding var selection: Selection
    let items: [(Selection, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Picker(title, selection: interceptBinding) {
                ForEach(items, id: \.0) { item in
                    Text(item.1).tag(item.0)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var interceptBinding: Binding<Selection> {
        Binding(
            get: { selection },
            set: { newValue in
                SoundEffects.shared.play(.selectionChange)
                selection = newValue
            }
        )
    }
}

private struct ButtonRow: View {
    let title: String
    var subtitle: String? = nil
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                SoundEffects.shared.play(.actionConfirm)
                action()
            }) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: "arrow.down.circle")
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.accentColor.opacity(0.12))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
            }
        }
    }
}

private struct TextFieldRow: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct ModelList: View {
    let title: String
    let records: [InstalledModelRecord]
    var onReveal: (InstalledModelRecord) -> Void
    var onDelete: (InstalledModelRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.secondary)
            ForEach(records, id: \.descriptor.id) { record in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.descriptor.name)
                            .font(.system(size: 13, weight: .medium))
                        Text("\(record.descriptor.provider) • \(formattedSize(record.descriptor.sizeMB))")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                    }
                    Spacer()
                    Button("Reveal") { onReveal(record) }
                    Button(role: .destructive) { onDelete(record) } label: { Text("Remove") }
                }
                .buttonStyle(.borderless)
                Divider()
            }
        }
    }

    private func formattedSize(_ size: Double) -> String {
        if size > 1024 {
            return String(format: "%.1f GB", size / 1024)
        } else {
            return String(format: "%.0f MB", size)
        }
    }
}

// Existing HotkeyRecorder and helper views remain unchanged below

struct HotkeyRecorder: NSViewRepresentable {
    var onRecord: (Hotkey?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = HotkeyRecorderView()
        view.onRecord = onRecord
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class HotkeyRecorderView: NSView {
        var onRecord: ((Hotkey?) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.type == .keyDown {
                let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
                let modifiers = event.modifierFlags
                var modArray: [String] = []
                if modifiers.contains(.command) { modArray.append("command") }
                if modifiers.contains(.option) { modArray.append("option") }
                if modifiers.contains(.control) { modArray.append("control") }
                if modifiers.contains(.shift) { modArray.append("shift") }
                if key.isEmpty || modArray.isEmpty {
                    onRecord?(nil)
                    return
                }
                let newHotkey = Hotkey(key: key, modifiers: modArray)
                if GlobalHotkeyManager.canRegister(hotkey: newHotkey) {
                    onRecord?(newHotkey)
                } else {
                    onRecord?(nil)
                }
            }
        }

        override func flagsChanged(with event: NSEvent) {
            if event.keyCode == 63 && event.modifierFlags.contains(.function) {
                onRecord?(Hotkey(key: "fn", modifiers: []))
            } else {
                super.flagsChanged(with: event)
            }
        }
    }
}

enum DictationRuntimeHelper {
    static func installFluidRuntime(progress: @escaping (String) -> Void = { _ in }) async throws -> URL {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let base = support.appendingPathComponent("mjvoice", isDirectory: true)
        let bin = base.appendingPathComponent("bin", isDirectory: true)
        let runner = bin.appendingPathComponent("fluid-runner")

        if fm.isExecutableFile(atPath: runner.path) {
            return runner
        }

        return try await FluidRuntimeInstaller.shared.install { message in
            progress(message)
        }
    }
}
