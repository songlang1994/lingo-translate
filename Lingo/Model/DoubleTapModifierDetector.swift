import AppKit

/// Detects two presses of the same bare modifier key (⌃ ⌥ ⌘ ⇧) within `interval`.
struct DoubleTapModifierDetector {
    /// The double-tap window is fixed at 300 ms and is not user configurable.
    static let interval: TimeInterval = 0.3

    private var pressedModifier: NSEvent.ModifierFlags?
    private var pendingModifier: NSEvent.ModifierFlags?
    private var pendingTapTime: TimeInterval?

    /// Feed a `.flagsChanged` event. Returns the modifier when a double tap completed.
    mutating func handleFlagsChanged(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        at time: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> NSEvent.ModifierFlags? {
        guard let changedModifier = KeyShortcut.modifier(forKeyCode: keyCode) else {
            clearPendingTap()
            return nil
        }

        guard modifierFlags.contains(changedModifier) else {
            if pressedModifier == changedModifier {
                pressedModifier = nil
            }
            return nil
        }

        // Ignore repeats while the same physical modifier is already held.
        guard pressedModifier != changedModifier else { return nil }
        pressedModifier = changedModifier

        let otherModifiers = modifierFlags
            .intersection(KeyShortcut.trackableModifiers)
            .subtracting(changedModifier)
        guard otherModifiers.isEmpty else {
            clearPendingTap()
            return nil
        }

        if pendingModifier == changedModifier,
           let pendingTapTime,
           time - pendingTapTime <= Self.interval {
            clearPendingTap()
            return changedModifier
        }

        pendingModifier = changedModifier
        pendingTapTime = time
        return nil
    }

    /// A regular key press means the modifier was used as part of a shortcut.
    mutating func handleKeyDown() {
        clearPendingTap()
    }

    mutating func reset() {
        pressedModifier = nil
        clearPendingTap()
    }

    private mutating func clearPendingTap() {
        pendingModifier = nil
        pendingTapTime = nil
    }
}
