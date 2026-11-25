import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let suspendHotKey: (Bool) -> Void

    var body: some View {
        Form {
            Section {
                TextField("Endpoint", text: $settings.endpoint, prompt: Text("https://api.openai.com/v1/responses"))
                TextField("Model", text: $settings.model, prompt: Text("gpt-4.1-mini"))
                SecureField("API key", text: $settings.apiKey)
            } footer: {
                Text("A base address such as https://api.openai.com/v1 is also accepted; /responses is appended automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Shortcut") {
                ShortcutRecorder(shortcut: $settings.shortcut, suspendHotKey: suspendHotKey)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 248)
    }
}
