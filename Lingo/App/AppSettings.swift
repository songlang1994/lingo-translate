import AppKit
import Combine

@MainActor
final class AppSettings: ObservableObject {
    private enum StorageKey {
        static let endpoint = "endpoint"
        static let model = "model"
        static let source = "sourceLanguage"
        static let target = "targetLanguage"
        static let shortcutKind = "shortcutKind"
        static let shortcutCode = "shortcutKeyCode"
        static let shortcutModifiers = "shortcutModifiers"
        static let shortcutDisplay = "shortcutDisplay"
    }

    private enum ShortcutKind {
        static let combination = "combination"
        static let doubleTapModifier = "doubleTapModifier"
    }

    private static let legacyDefaultShortcutDisplay = "⌥⌘L"

    static let defaultEndpoint = "https://api.openai.com/v1/responses"
    static let defaultModel = "gpt-4.1-mini"

    @Published var endpoint: String {
        didSet { defaults.set(endpoint, forKey: StorageKey.endpoint) }
    }

    @Published var model: String {
        didSet { defaults.set(model, forKey: StorageKey.model) }
    }

    @Published var apiKey: String {
        didSet { Self.storeAPIKey(apiKey) }
    }

    @Published var sourceCode: String {
        didSet { defaults.set(sourceCode, forKey: StorageKey.source) }
    }

    @Published var targetCode: String {
        didSet { defaults.set(targetCode, forKey: StorageKey.target) }
    }

    @Published var shortcut: KeyShortcut {
        didSet {
            switch shortcut {
            case let .combination(keyCode, modifiers, display):
                defaults.set(ShortcutKind.combination, forKey: StorageKey.shortcutKind)
                defaults.set(Int(keyCode), forKey: StorageKey.shortcutCode)
                defaults.set(Int(modifiers.rawValue), forKey: StorageKey.shortcutModifiers)
                defaults.set(display, forKey: StorageKey.shortcutDisplay)
            case let .doubleTapModifier(modifier):
                defaults.set(ShortcutKind.doubleTapModifier, forKey: StorageKey.shortcutKind)
                defaults.set(Int(modifier.rawValue), forKey: StorageKey.shortcutModifiers)
                defaults.removeObject(forKey: StorageKey.shortcutCode)
                defaults.removeObject(forKey: StorageKey.shortcutDisplay)
            }
        }
    }

    private let defaults = UserDefaults.standard

    init() {
        endpoint = defaults.string(forKey: StorageKey.endpoint) ?? Self.defaultEndpoint
        model = defaults.string(forKey: StorageKey.model) ?? Self.defaultModel
        sourceCode = defaults.string(forKey: StorageKey.source) ?? Language.automatic.code
        let storedTarget = defaults.string(forKey: StorageKey.target)
        targetCode = (storedTarget == nil || storedTarget == Language.automatic.code)
            ? Language.defaultTarget.code
            : storedTarget!
        shortcut = Self.loadShortcut()
        apiKey = Self.loadAPIKey()
    }

    var configuration: Configuration {
        Configuration(endpoint: endpoint, apiKey: apiKey, model: model)
    }

    var isReady: Bool {
        configuration.isConfigured
    }

    private static func loadShortcut() -> KeyShortcut {
        let defaults = UserDefaults.standard
        let kind = defaults.string(forKey: StorageKey.shortcutKind)
        let rawModifiers = UInt(defaults.integer(forKey: StorageKey.shortcutModifiers))
        let modifiers = NSEvent.ModifierFlags(rawValue: rawModifiers)

        if kind == ShortcutKind.doubleTapModifier {
            guard let modifier = KeyShortcut.singleModifier(in: modifiers) else {
                return .default
            }
            return .doubleTapModifier(modifier)
        }

        let storedDisplay = defaults.string(forKey: StorageKey.shortcutDisplay)
        // Versions without a stored kind only knew about key combinations.
        guard defaults.object(forKey: StorageKey.shortcutCode) != nil || storedDisplay != nil else {
            return .default
        }

        let keyCode = UInt16(defaults.integer(forKey: StorageKey.shortcutCode))
        return .combination(
            keyCode: keyCode,
            modifiers: modifiers,
            display: storedDisplay ?? legacyDefaultShortcutDisplay
        )
    }

    private static var apiKeyFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("Lingo", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("api-key")
    }

    private static func loadAPIKey() -> String {
        guard let data = try? Data(contentsOf: apiKeyFileURL),
              let key = String(data: data, encoding: .utf8) else {
            return ""
        }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func storeAPIKey(_ key: String) {
        let url = apiKeyFileURL
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }

        do {
            try Data(trimmed.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("Lingo: could not store API key: \(error)")
        }
    }
}
