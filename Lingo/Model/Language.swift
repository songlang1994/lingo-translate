import Foundation

struct Language: Identifiable, Hashable, Codable {
    let code: String
    let name: String

    var id: String { code }
    var isAutomatic: Bool { code == Self.automatic.code }

    static let automatic = Language(code: "auto", name: "Detect language")

    static let all: [Language] = [
        Language(code: "ar", name: "Arabic"),
        Language(code: "bn", name: "Bengali"),
        Language(code: "bg", name: "Bulgarian"),
        Language(code: "ca", name: "Catalan"),
        Language(code: "zh-Hans", name: "Chinese (Simplified)"),
        Language(code: "zh-Hant", name: "Chinese (Traditional)"),
        Language(code: "hr", name: "Croatian"),
        Language(code: "cs", name: "Czech"),
        Language(code: "da", name: "Danish"),
        Language(code: "nl", name: "Dutch"),
        Language(code: "en", name: "English"),
        Language(code: "et", name: "Estonian"),
        Language(code: "fi", name: "Finnish"),
        Language(code: "fr", name: "French"),
        Language(code: "de", name: "German"),
        Language(code: "el", name: "Greek"),
        Language(code: "he", name: "Hebrew"),
        Language(code: "hi", name: "Hindi"),
        Language(code: "hu", name: "Hungarian"),
        Language(code: "id", name: "Indonesian"),
        Language(code: "it", name: "Italian"),
        Language(code: "ja", name: "Japanese"),
        Language(code: "ko", name: "Korean"),
        Language(code: "lv", name: "Latvian"),
        Language(code: "lt", name: "Lithuanian"),
        Language(code: "ms", name: "Malay"),
        Language(code: "nb", name: "Norwegian"),
        Language(code: "fa", name: "Persian"),
        Language(code: "pl", name: "Polish"),
        Language(code: "pt-BR", name: "Portuguese (Brazil)"),
        Language(code: "pt-PT", name: "Portuguese (Portugal)"),
        Language(code: "ro", name: "Romanian"),
        Language(code: "ru", name: "Russian"),
        Language(code: "sr", name: "Serbian"),
        Language(code: "sk", name: "Slovak"),
        Language(code: "sl", name: "Slovenian"),
        Language(code: "es", name: "Spanish"),
        Language(code: "sv", name: "Swedish"),
        Language(code: "th", name: "Thai"),
        Language(code: "tr", name: "Turkish"),
        Language(code: "uk", name: "Ukrainian"),
        Language(code: "ur", name: "Urdu"),
        Language(code: "vi", name: "Vietnamese")
    ]

    static func named(_ code: String) -> Language {
        if code == automatic.code { return automatic }
        return all.first { $0.code == code } ?? Language(code: code, name: code)
    }

    static var defaultTarget: Language {
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("zh-Hans") || preferred.hasPrefix("zh-CN") {
            return named("zh-Hans")
        }
        if preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-TW") || preferred.hasPrefix("zh-HK") {
            return named("zh-Hant")
        }
        if let exact = all.first(where: { $0.code.caseInsensitiveCompare(preferred) == .orderedSame }) {
            return exact
        }
        let languageCode = String(preferred.prefix(2)).lowercased()
        if let regional = all.first(where: { $0.code.lowercased().hasPrefix(languageCode + "-") }) {
            return regional
        }
        return named(languageCode)
    }

    static var sourceOptions: [Language] {
        [automatic] + all
    }
}
