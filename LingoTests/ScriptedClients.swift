import XCTest
@testable import Lingo_Translate

/// Scripted translation and dictionary clients shared by the tests.
@MainActor
final class ScriptedClient: TranslationClient {
    enum Step {
        case reply(String)
        case delayedReply(String, nanoseconds: UInt64)
        case failure(Error)
    }

    var steps: [Step]
    private(set) var requests: [(instructions: String, input: String)] = []
    /// Characters streamed per request.
    private(set) var delivered: [Int] = []
    var deliveredCharacters: Int { delivered.reduce(0, +) }

    init(_ steps: [Step]) {
        self.steps = steps
    }

    func complete(
        instructions: String,
        input: String,
        configuration: Configuration,
        onDelta: @escaping (String) -> Void
    ) async throws -> String {
        requests.append((instructions, input))
        delivered.append(0)
        guard !steps.isEmpty else { throw URLError(.badServerResponse) }
        switch steps.removeFirst() {
        case let .failure(error):
            throw error
        case let .delayedReply(text, delay):
            try await Task.sleep(nanoseconds: delay)
            return try await stream(text, onDelta: onDelta)
        case let .reply(text):
            return try await stream(text, onDelta: onDelta)
        }
    }

    /// Streams in small chunks so partial parsing and cancellation are exercised.
    private func stream(_ text: String, onDelta: @escaping (String) -> Void) async throws -> String {
        var index = text.startIndex
        while index < text.endIndex {
            try Task.checkCancellation()
            let end = text.index(index, offsetBy: 7, limitedBy: text.endIndex) ?? text.endIndex
            onDelta(String(text[index..<end]))
            delivered[delivered.count - 1] += text.distance(from: index, to: end)
            index = end
            await Task.yield()
        }
        return text
    }
}

@MainActor
final class ScriptedDictionaryClient: DictionaryClient {
    var results: [DictionaryEntry?]
    var failure: Error?
    private(set) var terms: [String] = []

    init(_ results: [DictionaryEntry?] = []) {
        self.results = results
    }

    func lookup(
        term: String,
        source: Language,
        target: Language,
        configuration: Configuration
    ) async throws -> DictionaryEntry? {
        terms.append(term)
        if let failure { throw failure }
        return results.isEmpty ? nil : results.removeFirst()
    }
}
