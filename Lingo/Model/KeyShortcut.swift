import AppKit
import Carbon.HIToolbox

enum KeyShortcut: Equatable {
    /// A regular keyboard shortcut, for example ⌥⌘L.
    case combination(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, display: String)
    /// Two quick presses of a single modifier key, for example Control.
    case doubleTapModifier(NSEvent.ModifierFlags)

    static let trackableModifiers: NSEvent.ModifierFlags = [.control, .option, .command, .shift]

    static let `default` = KeyShortcut.combination(
        keyCode: UInt16(kVK_ANSI_L),
        modifiers: [.option, .command],
        display: "⌥⌘L"
    )

    var display: String {
        switch self {
        case let .combination(_, _, display):
            return display
        case let .doubleTapModifier(modifier):
            return "Double-tap \(Self.symbol(for: modifier))"
        }
    }

    var isDoubleTap: Bool {
        if case .doubleTapModifier = self { return true }
        return false
    }

    static func symbol(for modifier: NSEvent.ModifierFlags) -> String {
        if modifier.contains(.control) { return "⌃" }
        if modifier.contains(.option) { return "⌥" }
        if modifier.contains(.command) { return "⌘" }
        if modifier.contains(.shift) { return "⇧" }
        return ""
    }

    /// Returns the modifier whose physical key produced `keyCode`, if any.
    static func modifier(forKeyCode keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch Int(keyCode) {
        case kVK_Control, kVK_RightControl: return .control
        case kVK_Option, kVK_RightOption: return .option
        case kVK_Command, kVK_RightCommand: return .command
        case kVK_Shift, kVK_RightShift: return .shift
        default: return nil
        }
    }

    /// Returns the only modifier present in `modifiers`, or nil when zero or several are present.
    static func singleModifier(in modifiers: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags? {
        let present = [NSEvent.ModifierFlags.control, .option, .command, .shift]
            .filter { modifiers.contains($0) }
        return present.count == 1 ? present[0] : nil
    }

    static func display(for event: NSEvent) -> String? {
        let modifiers = event.modifierFlags.intersection(trackableModifiers)
        guard !modifiers.intersection([.command, .option, .control]).isEmpty else { return nil }

        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        text += name(for: event)
        return text
    }

    private static func name(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return, kVK_ANSI_KeypadEnter: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Forward Delete"
        case kVK_Escape: return "Esc"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        default:
            let characters = event.charactersIgnoringModifiers ?? ""
            let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            return trimmed.uppercased()
        }
    }
}
