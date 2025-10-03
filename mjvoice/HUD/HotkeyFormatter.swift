import Foundation

struct HotkeyFormatter {
    static func displayString(for hotkey: Hotkey) -> String {
        var components = hotkey.modifiers.map { modifierSymbol(for: $0) }
        let keyComponent = keySymbol(for: hotkey.key)
        if !keyComponent.isEmpty {
            components.append(keyComponent)
        }
        return components.isEmpty ? "" : components.joined(separator: " + ")
    }

    private static func modifierSymbol(for raw: String) -> String {
        switch raw.lowercased() {
        case "command": return "Cmd"
        case "option": return "Opt"
        case "control": return "Ctrl"
        case "shift": return "Shift"
        case "fn": return "Fn"
        default: return raw.capitalized
        }
    }

    private static func keySymbol(for raw: String) -> String {
        let lower = raw.lowercased()
        switch lower {
        case "space": return "Space"
        case "return": return "Return"
        case "escape": return "Esc"
        case "tab": return "Tab"
        case "delete": return "Delete"
        default:
            if lower.count == 1 {
                return lower.uppercased()
            }
            return raw.capitalized
        }
    }
}
