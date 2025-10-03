import Foundation
import AppKit

public struct Hotkey: Codable, Equatable {
    public var key: String
    public var modifiers: [String]
}

public enum DictationMode: String, Codable {
    case streaming
    case instant
    case notes
}

public enum PTTMode: String, Codable {
    case pressHold = "press-and-hold"
    case latch
    case toggle
}

public enum ModelSize: String, Codable {
    case tiny, base, small
}

public enum TonePreset: String, Codable {
    case neutral, professional, friendly
}

public enum ASRModel: String, Codable {
    case whisper, fluid
}

public enum NoiseModel: String, Codable {
    case rnnoise, dtln_rs
}

public struct AppPreset: Codable, Equatable {
    public var tone: TonePreset
    public var mode: DictationMode
    public var grammarPrompt: String
}

public struct UserPreferences: Codable {
    public var version: String
    public var hotkey: Hotkey
    public var micSource: String
    public var defaultMode: DictationMode
    public var pttMode: PTTMode
    public var offlineMode: Bool
    public var modelSize: ModelSize
    public var asrModel: ASRModel
    public var noiseModel: NoiseModel
    public var language: String
    public var theme: String
    public var tonePreset: TonePreset
    public var autoCapitalize: Bool
    public var removeFiller: Bool
    public var enableAIGrammar: Bool
    public var defaultGrammarPrompt: String
    public var customVocab: [String]
    public var perAppPresets: [String: AppPreset]
    public var hasCompletedOnboarding: Bool
    public var selectedASRModelID: String?
    public var selectedNoiseModelID: String?
}

public final class PreferencesStore {
    public static let shared = PreferencesStore()
    private let url: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let queue = DispatchQueue(label: "prefs.store.queue")

    public private(set) var current: UserPreferences

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = base.appendingPathComponent("mjvoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.url = appDir.appendingPathComponent("preferences.json")
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? Data(contentsOf: url), let prefs = try? decoder.decode(UserPreferences.self, from: data) {
            self.current = prefs
        } else {
            self.current = UserPreferences(
                version: "1.0",
                hotkey: Hotkey(key: "space", modifiers: ["command", "shift"]),
                micSource: "Built-in Microphone",
                defaultMode: .streaming,
                pttMode: .pressHold,
                offlineMode: true,
                modelSize: .small,
                asrModel: .whisper,
                noiseModel: .dtln_rs,
                language: "en",
                theme: "auto",
                tonePreset: .neutral,
                autoCapitalize: true,
                removeFiller: true,
                enableAIGrammar: false,
                defaultGrammarPrompt: "Fix grammar and improve clarity while maintaining the original meaning.",
                customVocab: ["mjvoice", "ClaudeAI", "SwiftUI"],
                perAppPresets: [
                    "com.apple.mail": AppPreset(tone: .professional, mode: .instant, grammarPrompt: "Make it professional and polite for email communication."),
                    "com.tinyspeck.slackmacgap": AppPreset(tone: .friendly, mode: .streaming, grammarPrompt: "Keep it casual and conversational for chat.")
                ],
                hasCompletedOnboarding: false,
                selectedASRModelID: nil,
                selectedNoiseModelID: nil
            )
            persist()
        }
    }

    public func update(_ mutate: (inout UserPreferences) -> Void) {
        queue.sync {
            var copy = current
            mutate(&copy)
            current = copy
            persist()
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(current)
            try data.write(to: url, options: [.atomic])
        } catch {
            NSLog("[PreferencesStore] Failed to persist: \(error)")
        }
    }

    @discardableResult
    public func importCustomVocab(from fileURL: URL) -> Int {
        guard let contents = try? String(contentsOf: fileURL) else { return 0 }
        let tokens = contents
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var added = 0
        update { prefs in
            for t in tokens where !prefs.customVocab.contains(t) {
                prefs.customVocab.append(t)
                added += 1
            }
        }
        return added
    }

    public func addCustomVocabularyTerm(_ term: String) {
        let cleaned = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        update { prefs in
            if !prefs.customVocab.contains(cleaned) {
                prefs.customVocab.append(cleaned)
                prefs.customVocab.sort()
            }
        }
    }

    public func removeCustomVocabularyTerm(_ term: String) {
        update { prefs in
            prefs.customVocab.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        }
    }
}
