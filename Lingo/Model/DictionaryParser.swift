import Foundation

/// Parses the dictionary reply. The model answers with one JSON object, but a
/// reply may arrive wrapped in a code fence or surrounded by prose; the parser
/// takes the outermost braces, matches keys case-insensitively, and drops
/// incomplete senses instead of failing the whole entry.
enum DictionaryParser {
    static let maximumSenses = 4
    static let maximumExamples = 2

    static func parse(_ reply: String) -> DictionaryEntry? {
        guard let first = reply.firstIndex(of: "{"),
              let last = reply.lastIndex(of: "}"),
              first < last else { return nil }
        let data = String(reply[first...last]).data(using: .utf8)
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else { return nil }

        let fields = normalized(root)
        guard isTrue(fields["valid"]) else { return nil }

        let term = text(fields["term"], limit: 80) ?? ""
        let pronunciation = text(fields["pronunciation"], limit: 80)
        let senses = (fields["senses"] as? [Any] ?? [])
            .compactMap { $0 as? [String: Any] }
            .compactMap(sense(from:))
            .prefix(maximumSenses)
        guard !senses.isEmpty else { return nil }

        return DictionaryEntry(term: term, pronunciation: pronunciation, senses: Array(senses))
    }

    // MARK: - Helpers

    /// Keys differ in case between models, so every lookup is lowercased.
    private static func normalized(_ object: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in object {
            result[key.lowercased()] = value
        }
        return result
    }

    private static func sense(from object: [String: Any]) -> DictionaryEntry.Sense? {
        let fields = normalized(object)
        guard let definition = text(fields["definition"], limit: 400) else { return nil }
        let partOfSpeech = text(fields["partofspeech"] ?? fields["pos"], limit: 24) ?? ""
        let examples = (fields["examples"] as? [Any] ?? [])
            .compactMap { $0 as? [String: Any] }
            .compactMap(example(from:))
            .prefix(maximumExamples)
        return DictionaryEntry.Sense(
            partOfSpeech: partOfSpeech,
            definition: definition,
            examples: Array(examples)
        )
    }

    private static func example(from object: [String: Any]) -> DictionaryEntry.Example? {
        let fields = normalized(object)
        guard let source = text(fields["source"], limit: 400) else { return nil }
        let translation = text(fields["translation"], limit: 400) ?? ""
        return DictionaryEntry.Example(source: source, translation: translation)
    }

    private static func text(_ value: Any?, limit: Int) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(limit))
    }

    private static func isTrue(_ value: Any?) -> Bool {
        switch value {
        case let flag as Bool:
            return flag
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            return ["true", "yes", "1"].contains(string.trimmingCharacters(in: .whitespaces).lowercased())
        default:
            return false
        }
    }
}
