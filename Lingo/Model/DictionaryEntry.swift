import Foundation

/// A dictionary entry shown under both columns for a word or short phrase.
struct DictionaryEntry: Equatable {
    struct Example: Equatable {
        var source: String
        var translation: String
    }

    struct Sense: Equatable {
        var partOfSpeech: String
        var definition: String
        var examples: [Example]
    }

    var term: String
    var pronunciation: String?
    var senses: [Sense]
}

enum DictionaryState: Equatable {
    case none
    case entry(DictionaryEntry)
}
