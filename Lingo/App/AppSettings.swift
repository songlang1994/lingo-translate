import AppKit
import Combine

@MainActor
final class AppSettings: ObservableObject {
    private enum StorageKey {
        static let endpoint = "endpoint"
        static let model = "model"
        static let reasoningEffort = "reasoningEffort"
        static let source = "sourceLanguage"
        static let target = "targetLanguage"
        static let shortcutKind = "shortcutKind"
        static let shortcutCode = "shortcutKeyCode"
        static let shortcutModifiers = "shortcutModifiers"
        static let shortcutDisplay = "shortcutDisplay"
        static let dictionaryHeight = "dictionaryHeight"
    }

    private enum ShortcutKind {
        static let combination = "combination"
        static let doubleTapModifier = "doubleTapModifier"
    }

    static let defaultEndpoint = "https://api.openai.com/v1/responses"
    static let defaultModel = "gpt-4.1-mini"
    static let defaultReasoningEffort: ReasoningEffort = .none
    static let defaultDictionaryHeight: CGFloat = 200

    @Published var endpoint: String {
        didSet { defaults.set(endpoint, forKey: StorageKey.endpoint) }
    }

    @Published var model: String {
        didSet { defaults.set(model, forKey: StorageKey.model) }
    }

    @Published var reasoningEffort: ReasoningEffort {
        didSet { defaults.set(reasoningEffort.rawValue, forKey: StorageKey.reasoningEffort) }
    }

    @Published var apiKey: String {
        didSet { APIKeyStore.save(apiKey) }
    }

    @Published var sourceCode: String {
        didSet { defaults.set(sourceCode, forKey: StorageKey.source) }
    }

    @Published var targetCode: String {
        didSet { defaults.set(targetCode, forKey: StorageKey.target) }
    }

    /// Height of the dictionary pane in points, remembered across launches.
    @Published var dictionaryHeight: CGFloat {
        didSet { defaults.set(Double(dictionaryHeight), forKey: StorageKey.dictionaryHeight) }
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
        if let stored = defaults.string(forKey: StorageKey.reasoningEffort),
           let effort = ReasoningEffort(rawValue: stored) {
            reasoningEffort = effort
        } else {
            // Stored values outside the presets, including ones from older versions, fall back to none.
            reasoningEffort = Self.defaultReasoningEffort
        }
        sourceCode = defaults.string(forKey: StorageKey.source) ?? Language.automatic.code
        let storedTarget = defaults.string(forKey: StorageKey.target)
        targetCode = (storedTarget == nil || storedTarget == Language.automatic.code)
            ? Language.defaultTarget.code
            : storedTarget!
        let storedDictionaryHeight = CGFloat(defaults.double(forKey: StorageKey.dictionaryHeight))
        dictionaryHeight = storedDictionaryHeight > 0 ? storedDictionaryHeight : Self.defaultDictionaryHeight
        shortcut = Self.loadShortcut()
        apiKey = APIKeyStore.load()
    }

    var configuration: Configuration {
        Configuration(
            endpoint: endpoint,
            apiKey: apiKey,
            model: model,
            reasoningEffort: reasoningEffort
        )
    }

    var isReady: Bool {
        configuration.isConfigured
    }

    private static func loadShortcut() -> KeyShortcut {
        let defaults = UserDefaults.standard
        let rawModifiers = UInt(defaults.integer(forKey: StorageKey.shortcutModifiers))
        let modifiers = NSEvent.ModifierFlags(rawValue: rawModifiers)

        switch defaults.string(forKey: StorageKey.shortcutKind) {
        case ShortcutKind.doubleTapModifier:
            guard let modifier = KeyShortcut.singleModifier(in: modifiers) else {
                return .default
            }
            return .doubleTapModifier(modifier)
        case ShortcutKind.combination:
            guard let display = defaults.string(forKey: StorageKey.shortcutDisplay) else {
                return .default
            }
            let keyCode = UInt16(defaults.integer(forKey: StorageKey.shortcutCode))
            return .combination(keyCode: keyCode, modifiers: modifiers, display: display)
        default:
            return .default
        }
    }
}
