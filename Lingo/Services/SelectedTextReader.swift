import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Reads the text selected in another application before the panel takes focus.
/// The Accessibility API answers without touching the pasteboard; apps that do
/// not expose their selection (some web and Electron views) are asked to copy
/// it instead, and the user's pasteboard is restored afterwards.
@MainActor
enum SelectedTextReader {
    static func selectedText(in app: NSRunningApplication?) -> String? {
        guard AccessibilityPermission.isGranted,
              let app,
              app != NSRunningApplication.current
        else { return nil }

        let pid = app.processIdentifier
        if let text = accessibilitySelectedText(pid: pid), !isBlank(text) {
            return text
        }
        if let text = copiedSelectedText(pid: pid), !isBlank(text) {
            return text
        }
        return nil
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Accessibility

    private static func accessibilitySelectedText(pid: pid_t) -> String? {
        let application = AXUIElementCreateApplication(pid)
        guard let focusedValue = copyAttribute(application, kAXFocusedUIElementAttribute),
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else { return nil }
        let focused = focusedValue as! AXUIElement

        if let selected = copyAttribute(focused, kAXSelectedTextAttribute) as? String,
           !isBlank(selected) {
            return selected
        }

        // Some elements expose only the selected range over a value.
        guard let string = copyAttribute(focused, kAXValueAttribute) as? String,
              let rangeValue = copyAttribute(focused, kAXSelectedTextRangeAttribute),
              CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else { return nil }

        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return nil }
        return substring(of: string, inRange: range)
    }

    /// The part of `value` covered by an Accessibility range, or nil when the
    /// range is empty or outside it.
    static func substring(of value: String, inRange range: CFRange) -> String? {
        guard range.length > 0, range.location >= 0 else { return nil }
        let text = value as NSString
        guard range.location + range.length <= text.length else { return nil }
        return text.substring(with: NSRange(location: range.location, length: range.length))
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    // MARK: - Pasteboard fallback

    private static func copiedSelectedText(pid: pid_t) -> String? {
        let pasteboard = NSPasteboard.general
        let savedSnapshot = snapshot(of: pasteboard)
        let previousChangeCount = pasteboard.changeCount

        postCopy(to: pid)

        // The other app performs the copy on its own main run loop.
        let deadline = Date().addingTimeInterval(0.3)
        while pasteboard.changeCount == previousChangeCount, Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        guard pasteboard.changeCount != previousChangeCount else { return nil }

        // Let the source app finish writing every representation.
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        let text = pasteboard.string(forType: .string)

        restore(savedSnapshot, to: pasteboard)
        return text
    }

    /// Pasteboard items belong to the app that wrote them, so copy their data
    /// before they are replaced.
    static func snapshot(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    contents[type] = data
                }
            }
            return contents
        }
    }

    static func restore(_ snapshot: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items = snapshot.compactMap { contents -> NSPasteboardItem? in
            guard !contents.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for (type, data) in contents {
                item.setData(data, forType: type)
            }
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    /// Sends ⌘C to the app, so its current selection lands on the pasteboard.
    private static func postCopy(to pid: pid_t) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
    }
}
