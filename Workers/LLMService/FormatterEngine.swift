import Foundation

final class FormatterEngine {
    func format(text: String, config: LLMConfig) -> String {
        var s = text
        if config.removeFiller {
            s = removeFillerWords(s)
        }
        s = smartPunctuation(s)
        if config.autoCapitalize {
            s = capitalizeSentences(s)
        }
        switch config.tone.lowercased() {
        case "professional": s = applyToneProfessional(s)
        case "friendly": s = applyToneFriendly(s)
        default: break
        }
        return s
    }

    private func removeFillerWords(_ s: String) -> String {
        let fillers = ["um", "uh", "like", "you know", "sort of", "kind of"]
        var out = s
        for f in fillers { out = out.replacingOccurrences(of: "\\b\(f)\\b", with: "", options: [.regularExpression, .caseInsensitive]) }
        return out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func smartPunctuation(_ s: String) -> String {
        // naive sentence end detection
        var out = s
        if !out.hasSuffix(".") && !out.hasSuffix("!") && !out.hasSuffix("?") {
            out += "."
        }
        out = out.replacingOccurrences(of: " ,", with: ",")
        return out
    }

    private func capitalizeSentences(_ s: String) -> String {
        let sentences = s.split(whereSeparator: { [".", "!", "?"].contains(String($0)) })
        var result = s
        if let first = sentences.first {
            let trimmed = first.trimmingCharacters(in: .whitespaces)
            if let range = result.range(of: trimmed) {
                result.replaceSubrange(range, with: trimmed.capitalized)
            }
        }
        return result
    }

    private func applyToneProfessional(_ s: String) -> String {
        return s.replacingOccurrences(of: "!", with: ".")
    }

    private func applyToneFriendly(_ s: String) -> String {
        return s.replacingOccurrences(of: ".", with: "!")
    }
}
