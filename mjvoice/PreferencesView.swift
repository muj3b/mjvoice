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

    private let modelManager = ModelManager.shared

    var body: some View {
        Form {
            Section(header: Text("General")) {
                HStack {
                    Text("Hotkey:")
                    if recordingHotkey {
                        HotkeyRecorder(onRecord: { newHotkey in
                            recordingHotkey = false
                            if let newHotkey = newHotkey {
                                update { $0.hotkey = newHotkey }
                                GlobalHotkeyManager.shared.registerDefaultHotkey()
                                hotkeyError = nil
                            } else {
                                hotkeyError = "Invalid hotkey or already in use"
                            }
                        })
                    } else {
                        Text(displayHotkey(prefs.hotkey))
                        Button("Change") {
                            recordingHotkey = true
                            hotkeyError = nil
                        }
                    }
                }
                if let error = hotkeyError {
                    Text(error).foregroundColor(.red).font(.caption)
                }
                Toggle("Offline Mode", isOn: Binding(
                    get: { prefs.offlineMode },
                    set: { new in update { $0.offlineMode = new } }
                ))
                Picker("Default Mode", selection: Binding(
                    get: { prefs.defaultMode },
                    set: { new in update { $0.defaultMode = new } }
                )) {
                    Text("Streaming").tag(DictationMode.streaming)
                    Text("Instant").tag(DictationMode.instant)
                    Text("Notes").tag(DictationMode.notes)
                }
                Picker("PTT Mode", selection: Binding(
                    get: { prefs.pttMode },
                    set: { new in 
                        update { $0.pttMode = new }
                        GlobalHotkeyManager.shared.configure(mode: new)
                    }
                )) {
                    Text("Press and Hold").tag(PTTMode.pressHold)
                    Text("Latch").tag(PTTMode.latch)
                    Text("Toggle").tag(PTTMode.toggle)
                }
                Picker("Model Size", selection: Binding(
                    get: { prefs.modelSize },
                    set: { new in update { $0.modelSize = new } }
                )) {
                    Text("Tiny").tag(ModelSize.tiny)
                    Text("Base").tag(ModelSize.base)
                    Text("Small").tag(ModelSize.small)
                }
                Picker("ASR Model", selection: Binding(
                    get: { prefs.asrModel },
                    set: { new in update { $0.asrModel = new } }
                )) {
                    Text("Whisper (OpenAI)").tag(ASRModel.whisper)
                    Text("Fluid Audio").tag(ASRModel.fluid)
                }
                Picker("Noise Suppression", selection: Binding(
                    get: { prefs.noiseModel },
                    set: { new in update { $0.noiseModel = new } }
                )) {
                    Text("RNNoise (2024)").tag(NoiseModel.rnnoise)
                    Text("dtln-rs (2025)").tag(NoiseModel.dtln_rs)
                }
                TextField("Language", text: Binding(
                    get: { prefs.language },
                    set: { new in update { $0.language = new } }
                ))
                Toggle("Auto Capitalize", isOn: Binding(
                    get: { prefs.autoCapitalize },
                    set: { new in update { $0.autoCapitalize = new } }
                ))
                Toggle("Remove Filler Words", isOn: Binding(
                    get: { prefs.removeFiller },
                    set: { new in update { $0.removeFiller = new } }
                ))
            }
            Section(header: Text("Models")) {
                Picker("Active ASR Model", selection: Binding(
                    get: { prefs.selectedASRModelID ?? modelIdentifierDefault(for: prefs) },
                    set: { new in update { $0.selectedASRModelID = new } }
                )) {
                    Text(defaultModelDisplay(for: prefs)).tag(modelIdentifierDefault(for: prefs))
                    ForEach(installedASR, id: \.descriptor.id) { record in
                        Text("\(record.descriptor.name) — \(record.descriptor.provider)")
                            .tag(record.descriptor.id)
                    }
                }
                if isDownloadingASR {
                    ProgressView(value: asrDownloadProgress, total: 1.0) {
                        Text("Downloading ASR model…")
                    }
                }
                Button("Download \(prefs.asrModel == .whisper ? "Whisper" : "Fluid") \(prefs.modelSize.rawValue.capitalized) Model") {
                    startASRDownload()
                }
                Button("Add Custom ASR Model…") {
                    importCustomModel(kind: .asr)
                }
                if !installedASR.isEmpty {
                    ForEach(installedASR, id: \.descriptor.id) { record in
                        ModelRow(record: record, onReveal: revealModel, onDelete: deleteModel)
                    }
                }
                Divider()
                Picker("Noise Suppression", selection: Binding(
                    get: { prefs.selectedNoiseModelID ?? defaultNoiseIdentifier(for: prefs.noiseModel) },
                    set: { new in update { $0.selectedNoiseModelID = new } }
                )) {
                    Text(defaultNoiseDisplay(for: prefs)).tag(defaultNoiseIdentifier(for: prefs.noiseModel))
                    ForEach(installedNoise, id: \.descriptor.id) { record in
                        Text("\(record.descriptor.name)").tag(record.descriptor.id)
                    }
                }
                if isDownloadingNoise {
                    ProgressView(value: noiseDownloadProgress, total: 1.0) {
                        Text("Downloading noise model…")
                    }
                }
                Button("Download \(prefs.noiseModel == .dtln_rs ? "dtln-rs" : "RNNoise") Model") {
                    startNoiseDownload()
                }
                Button("Add Custom Noise Model…") {
                    importCustomModel(kind: .noise)
                }
                if !installedNoise.isEmpty {
                    ForEach(installedNoise, id: \.descriptor.id) { record in
                        ModelRow(record: record, onReveal: revealModel, onDelete: deleteModel)
                    }
                }
            }
            Section(header: Text("AI Grammar")) {
                Toggle("Enable AI Grammar Fixing", isOn: Binding(
                    get: { prefs.enableAIGrammar },
                    set: { new in update { $0.enableAIGrammar = new } }
                ))
                TextField("Default Grammar Prompt", text: Binding(
                    get: { prefs.defaultGrammarPrompt },
                    set: { new in update { $0.defaultGrammarPrompt = new } }
                ))
            }
            Section(header: Text("Theme")) {
                Picker("Theme", selection: Binding(
                    get: { prefs.theme },
                    set: { new in update { $0.theme = new } }
                )) {
                    Text("Auto").tag("auto")
                    Text("Light Glass").tag("light")
                    Text("Dark Glass").tag("dark")
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .frame(width: 460)
        .onAppear(perform: refreshModels)
        .onReceive(NotificationCenter.default.publisher(for: ModelManager.modelsDidChangeNotification)) { _ in
            refreshModels()
        }
        .alert(alertMessage ?? "", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        }
    }

    private func update(_ mutate: (inout UserPreferences) -> Void) {
        PreferencesStore.shared.update { pr in
            mutate(&pr)
            prefs = pr
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
            case .failure(let error):
                alert(error.localizedDescription)
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
            case .failure(let error):
                alert(error.localizedDescription)
            }
        }
    }

    private func importCustomModel(kind: ModelKind) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let record = try modelManager.registerCustomModel(from: url, name: url.deletingPathExtension().lastPathComponent, kind: kind)
                if kind == .asr {
                    update { $0.selectedASRModelID = record.descriptor.id }
                } else {
                    update { $0.selectedNoiseModelID = record.descriptor.id }
                }
                refreshModels()
            } catch {
                alert("Failed to import model: \(error.localizedDescription)")
            }
        }
    }

    private func revealModel(_ record: InstalledModelRecord) {
        let url = modelManager.location(for: record.descriptor.id)
        if let url {
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

private struct ModelRow: View {
    let record: InstalledModelRecord
    var onReveal: (InstalledModelRecord) -> Void
    var onDelete: (InstalledModelRecord) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(record.descriptor.name)
                    .font(.headline)
                Text("\(record.descriptor.provider) • \(formattedSize(record.descriptor.sizeMB))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reveal") { onReveal(record) }
            Button(role: .destructive) { onDelete(record) } label: { Text("Remove") }
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
