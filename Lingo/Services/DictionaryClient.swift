import Foundation

@MainActor
protocol DictionaryClient: AnyObject {
    /// Returns nil when the model decides the text is not a word or phrase.
    func lookup(
        term: String,
        source: Language,
        target: Language,
        configuration: Configuration
    ) async throws -> DictionaryEntry?
}

/// Reuses the Responses client: the dictionary is one more plain request whose
/// streamed deltas are ignored.
@MainActor
final class ResponsesDictionaryClient: DictionaryClient {
    private let client: TranslationClient

    init(client: TranslationClient? = nil) {
        self.client = client ?? ResponsesClient()
    }

    func lookup(
        term: String,
        source: Language,
        target: Language,
        configuration: Configuration
    ) async throws -> DictionaryEntry? {
        let reply = try await client.complete(
            instructions: Prompt.dictionaryInstructions(source: source, target: target),
            input: term,
            configuration: configuration,
            onDelta: { _ in }
        )
        return DictionaryParser.parse(reply)
    }
}
