import Foundation

/// Decides locally whether the text could be a single word or a short phrase.
/// The check is deliberately loose: the model answers `valid: false` for
/// phrases that are really sentences, which only costs a request that runs
/// alongside the translation anyway.
enum DictionaryDetector {
    /// Texts written with spaces get a word budget.
    static let maximumWords = 4
    static let maximumTokenLength = 64
    /// Han, kana, and hangul are written without spaces, so they get a
    /// character budget instead.
    static let maximumIdeographicCharacters = 12

    /// Characters that only appear in code, markup, or addresses.
    private static let forbidden: Set<Character> = [
        "`", "{", "}", "<", ">", "\\", "|", "=", "@", "#", "*", "~", "^", "&", "$", "%", "[", "]", "(", ")"
    ]
    /// Punctuation inside the text means it is a sentence, not a term.
    private static let internalPunctuation: Set<Character> = [
        ".", ",", "!", "?", ";", ":", "。", "，", "！", "？", "；", "：", "、"
    ]
    private static let edgePunctuation = CharacterSet(charactersIn: "\"'“”‘’.,!?;:、。，！？；：…")

    static func isTerm(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else { return false }
        guard !trimmed.contains("://") else { return false }
        guard !trimmed.contains(where: forbidden.contains) else { return false }

        // Selecting with the pointer often carries quotes or the sentence mark.
        let core = trimmed.trimmingCharacters(in: edgePunctuation)
        guard !core.isEmpty, core.contains(where: \.isLetter) else { return false }
        guard !core.contains(where: internalPunctuation.contains) else { return false }

        if core.contains(where: isIdeographic) {
            return core.count(where: { !$0.isWhitespace }) <= maximumIdeographicCharacters
        }

        let words = core.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty, words.count <= maximumWords else { return false }
        return words.allSatisfy { $0.count <= maximumTokenLength }
    }

    private static func isIdeographic(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
                 0xF900...0xFAFF, 0xAC00...0xD7AF, 0x20000...0x2FA1F:
                return true
            default:
                return false
            }
        }
    }
}
