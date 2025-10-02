import Foundation

public final class TextFormatter {
    public static let shared = TextFormatter()

    private let fillerWords = Set(["um", "uh", "like", "you know", "so", "well", "actually", "basically", "literally", "kinda", "sorta", "i mean"])

    public func format(text: String, prefs: UserPreferences, appBundleId: String? = nil) -> String {
        var formatted = text

        // Get app-specific settings
        let appPreset = appBundleId.flatMap { prefs.perAppPresets[$0] }
        let tone = appPreset?.tone ?? prefs.tonePreset
        let grammarPrompt = appPreset?.grammarPrompt ?? prefs.defaultGrammarPrompt

        // Remove filler words
        if prefs.removeFiller {
            formatted = removeFillerWords(from: formatted)
        }

        // Smart punctuation
        formatted = addSmartPunctuation(to: formatted)

        // Capitalize sentences
        if prefs.autoCapitalize {
            formatted = capitalizeSentences(in: formatted)
        }

        // Apply tone preset
        formatted = applyTonePreset(to: formatted, tone: tone)

        // Basic grammar fixes
        formatted = fixBasicGrammar(in: formatted)

        // AI grammar fixing
        if prefs.enableAIGrammar {
            formatted = aiGrammarFix(text: formatted, prompt: grammarPrompt)
        }

        return formatted
    }

    private func removeFillerWords(from text: String) -> String {
        let words = text.split(separator: " ").map { String($0) }
        let filtered = words.filter { !fillerWords.contains($0.lowercased()) }
        return filtered.joined(separator: " ")
    }

    private func addSmartPunctuation(to text: String) -> String {
        var result = text

        // Add periods at end of sentences if missing
        result = result.replacingOccurrences(of: #"(?<!\.)\s*$"#, with: ".", options: .regularExpression)

        // Add commas before conjunctions
        result = result.replacingOccurrences(of: #"\s+(and|but|or|so|because)\s+"#, with: ", $1 ", options: .regularExpression, range: nil)

        // Add question marks
        result = result.replacingOccurrences(of: #"(what|where|when|why|how|who|which)\s+.*?(?=\s|$)"#, with: "$1?", options: .regularExpression, range: nil)

        return result
    }

    private func capitalizeSentences(in text: String) -> String {
        let sentences = text.split(separator: ".").map { String($0) }
        let capitalized = sentences.map { sentence in
            guard let first = sentence.first else { return sentence }
            return String(first).uppercased() + String(sentence.dropFirst())
        }
        return capitalized.joined(separator: ". ")
    }

    private func applyTonePreset(to text: String, tone: TonePreset) -> String {
        switch tone {
        case .neutral:
            return text
        case .professional:
            // More formal language
            return text.replacingOccurrences(of: "kinda", with: "somewhat")
                .replacingOccurrences(of: "sorta", with: "rather")
                .replacingOccurrences(of: "gonna", with: "going to")
                .replacingOccurrences(of: "wanna", with: "want to")
        case .friendly:
            // Add friendly touches
            return text.replacingOccurrences(of: "I think", with: "I believe")
                .replacingOccurrences(of: "probably", with: "likely")
        }
    }

    private func fixBasicGrammar(in text: String) -> String {
        var result = text

        // Fix contractions
        result = result.replacingOccurrences(of: "i ", with: "I ")
        result = result.replacingOccurrences(of: " im ", with: " I'm ")
        result = result.replacingOccurrences(of: " dont ", with: " don't ")
        result = result.replacingOccurrences(of: " cant ", with: " can't ")
        result = result.replacingOccurrences(of: " wont ", with: " won't ")
        result = result.replacingOccurrences(of: " isnt ", with: " isn't ")
        result = result.replacingOccurrences(of: " arent ", with: " aren't ")
        result = result.replacingOccurrences(of: " wasnt ", with: " wasn't ")
        result = result.replacingOccurrences(of: " werent ", with: " weren't ")
        result = result.replacingOccurrences(of: " hasnt ", with: " hasn't ")
        result = result.replacingOccurrences(of: " havent ", with: " haven't ")
        result = result.replacingOccurrences(of: " doesnt ", with: " doesn't ")
        result = result.replacingOccurrences(of: " didnt ", with: " didn't ")
        result = result.replacingOccurrences(of: " wouldnt ", with: " wouldn't ")
        result = result.replacingOccurrences(of: " shouldnt ", with: " shouldn't ")
        result = result.replacingOccurrences(of: " couldnt ", with: " couldn't ")
        result = result.replacingOccurrences(of: " its ", with: " it's ")
        return result
    }

    private func aiGrammarFix(text: String, prompt: String) -> String {
        // Placeholder for LLM integration
        // In real implementation, call local LLM with prompt
        // For now, return text as is or apply basic fixes
        return text // TODO: Integrate local LLM like Llama.cpp or similar
    }
}
