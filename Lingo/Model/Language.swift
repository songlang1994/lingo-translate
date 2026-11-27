import Foundation

struct Language: Identifiable, Hashable, Codable {
    let code: String
    /// English name, used in model prompts.
    let name: String
    /// Name written in the language itself, used in the language menus.
    let nativeName: String

    var id: String { code }
    var isAutomatic: Bool { code == Self.automatic.code }

    static let automatic = Language(code: "auto", name: "Detect language", nativeName: "Detect language")

    static let all: [Language] = [
        Language(code: "ar", name: "Arabic", nativeName: "العربية"),
        Language(code: "bn", name: "Bengali", nativeName: "বাংলা"),
        Language(code: "bg", name: "Bulgarian", nativeName: "Български"),
        Language(code: "ca", name: "Catalan", nativeName: "Català"),
        Language(code: "zh-Hans", name: "Chinese (Simplified)", nativeName: "简体中文"),
        Language(code: "zh-Hant", name: "Chinese (Traditional)", nativeName: "繁體中文"),
        Language(code: "hr", name: "Croatian", nativeName: "Hrvatski"),
        Language(code: "cs", name: "Czech", nativeName: "Čeština"),
        Language(code: "da", name: "Danish", nativeName: "Dansk"),
        Language(code: "nl", name: "Dutch", nativeName: "Nederlands"),
        Language(code: "en", name: "English", nativeName: "English"),
        Language(code: "et", name: "Estonian", nativeName: "Eesti"),
        Language(code: "fi", name: "Finnish", nativeName: "Suomi"),
        Language(code: "fr", name: "French", nativeName: "Français"),
        Language(code: "de", name: "German", nativeName: "Deutsch"),
        Language(code: "el", name: "Greek", nativeName: "Ελληνικά"),
        Language(code: "he", name: "Hebrew", nativeName: "עברית"),
        Language(code: "hi", name: "Hindi", nativeName: "हिन्दी"),
        Language(code: "hu", name: "Hungarian", nativeName: "Magyar"),
        Language(code: "id", name: "Indonesian", nativeName: "Bahasa Indonesia"),
        Language(code: "it", name: "Italian", nativeName: "Italiano"),
        Language(code: "ja", name: "Japanese", nativeName: "日本語"),
        Language(code: "ko", name: "Korean", nativeName: "한국어"),
        Language(code: "lv", name: "Latvian", nativeName: "Latviešu"),
        Language(code: "lt", name: "Lithuanian", nativeName: "Lietuvių"),
        Language(code: "ms", name: "Malay", nativeName: "Bahasa Melayu"),
        Language(code: "nb", name: "Norwegian", nativeName: "Norsk bokmål"),
        Language(code: "fa", name: "Persian", nativeName: "فارسی"),
        Language(code: "pl", name: "Polish", nativeName: "Polski"),
        Language(code: "pt-BR", name: "Portuguese (Brazil)", nativeName: "Português (Brasil)"),
        Language(code: "pt-PT", name: "Portuguese (Portugal)", nativeName: "Português (Portugal)"),
        Language(code: "ro", name: "Romanian", nativeName: "Română"),
        Language(code: "ru", name: "Russian", nativeName: "Русский"),
        Language(code: "sr", name: "Serbian", nativeName: "Српски"),
        Language(code: "sk", name: "Slovak", nativeName: "Slovenčina"),
        Language(code: "sl", name: "Slovenian", nativeName: "Slovenščina"),
        Language(code: "es", name: "Spanish", nativeName: "Español"),
        Language(code: "sv", name: "Swedish", nativeName: "Svenska"),
        Language(code: "th", name: "Thai", nativeName: "ไทย"),
        Language(code: "tr", name: "Turkish", nativeName: "Türkçe"),
        Language(code: "uk", name: "Ukrainian", nativeName: "Українська"),
        Language(code: "ur", name: "Urdu", nativeName: "اردو"),
        Language(code: "vi", name: "Vietnamese", nativeName: "Tiếng Việt")
    ]

    static func named(_ code: String) -> Language {
        if code == automatic.code { return automatic }
        return all.first { $0.code == code } ?? Language(code: code, name: code, nativeName: code)
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
