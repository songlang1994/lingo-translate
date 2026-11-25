import AppKit
import SwiftUI

struct ShortcutRecorder: View {
    @Binding var shortcut: KeyShortcut
    let suspendHotKey: (Bool) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var detector = DoubleTapModifierDetector()

    var body: some View {
        Button {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        } label: {
            Text(isRecording ? "…" : shortcut.display)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .frame(minWidth: 52)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isRecording ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("Press a key combination, or double-tap ⌃ ⌥ ⌘ ⇧")
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        detector.reset()
        suspendHotKey(true)

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .flagsChanged:
            let modifier = detector.handleFlagsChanged(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags,
                at: event.timestamp
            )
            if let modifier {
                shortcut = .doubleTapModifier(modifier)
                stopRecording()
                // Only ask for Accessibility access when a double-tap shortcut is actually chosen.
                if !AccessibilityPermission.isGranted {
                    AccessibilityPermission.prompt()
                }
            }
            // Consume modifier presses so they do not reach the rest of the window.
            return nil

        case .keyDown:
            detector.handleKeyDown()

            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            guard let display = KeyShortcut.display(for: event) else {
                NSSound.beep()
                return nil
            }

            shortcut = .combination(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags.intersection(KeyShortcut.trackableModifiers),
                display: display
            )
            stopRecording()
            return nil

        default:
            return event
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        suspendHotKey(false)

        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
