import SwiftUI

struct PreferencesView: View {
    @State private var prefs = PreferencesStore.shared.current
    @State private var recordingHotkey = false
    @State private var hotkeyError: String? = nil

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
                        Text(prefs.hotkey.modifiers.joined(separator: "+") + "+" + prefs.hotkey.key)
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
    }

    private func update(_ mutate: (inout UserPreferences) -> Void) {
        PreferencesStore.shared.update { pr in
            mutate(&pr)
            prefs = pr
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
    }
}
