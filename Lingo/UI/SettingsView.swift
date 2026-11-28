import AppKit
import Combine
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let suspendHotKey: (Bool) -> Void

    @State private var accessibilityGranted = AccessibilityPermission.isGranted

    var body: some View {
        Form {
            TextField("Endpoint", text: $settings.endpoint, prompt: Text("https://api.openai.com/v1/responses"))
            TextField("Model", text: $settings.model, prompt: Text("gpt-4.1-mini"))
            SecureField("API key", text: $settings.apiKey)
            Picker("Reasoning effort", selection: $settings.reasoningEffort) {
                ForEach(ReasoningEffort.allCases) { effort in
                    Text(effort.title).tag(effort)
                }
            }
            LabeledContent("Shortcut") {
                ShortcutRecorder(shortcut: $settings.shortcut, suspendHotKey: suspendHotKey)
            }
            Text("While recording, press a key combination or double-tap ⌃ ⌥ ⌘ ⇧.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !accessibilityGranted {
                accessibilityWarning
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 265)
        .onAppear {
            refreshAccessibilityStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityStatus()
        }
    }

    private var accessibilityWarning: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("Double-tap shortcuts and auto-filling the selected text need Accessibility access.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Open System Settings") {
                AccessibilityPermission.request()
            }
            .controlSize(.small)
        }
        .font(.caption)
    }

    private func refreshAccessibilityStatus() {
        accessibilityGranted = AccessibilityPermission.isGranted
    }
}
