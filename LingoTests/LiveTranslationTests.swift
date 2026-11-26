import XCTest
@testable import Lingo_Translate

/// Opt-in end-to-end check against a real endpoint. Skipped unless the
/// environment provides credentials, e.g. from the repository's `.env`:
///
///     set -a && . ./.env && set +a
///     TEST_RUNNER_LINGO_API_ENDPOINT="$LINGO_API_ENDPOINT" TEST_RUNNER_LINGO_MODEL="$LINGO_MODEL" \
///     TEST_RUNNER_LINGO_API_KEY="$LINGO_API_KEY" make test
@MainActor
final class LiveTranslationTests: XCTestCase {
    private final class EnvironmentClient: TranslationClient {
        let base = ResponsesClient()
        let configuration: Configuration

        init(configuration: Configuration) {
            self.configuration = configuration
        }

        func complete(
            instructions: String,
            input: String,
            configuration _: Configuration,
            onDelta: @escaping (String) -> Void
        ) async throws -> String {
            try await base.complete(instructions: instructions, input: input, configuration: configuration, onDelta: onDelta)
        }
    }

    func testManDescriptionIsTranslatedInThreeSegments() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let key = environment["LINGO_API_KEY"], !key.isEmpty,
              let endpoint = environment["LINGO_API_ENDPOINT"],
              let modelName = environment["LINGO_MODEL"] else {
            throw XCTSkip("Set LINGO_API_ENDPOINT, LINGO_MODEL and LINGO_API_KEY to run live tests.")
        }

        let text = """
        DESCRIPTION
             The grep utility searches any given input files, selecting lines that match one or more patterns.  By default, a pattern matches an input line if the regular expression (RE) in the pattern matches the input
             line without its trailing newline.  An empty expression matches every line.  Each input line that matches at least one of the patterns is written to the standard output.

             grep is used for simple patterns and basic regular expressions (BREs); egrep can handle extended regular expressions (EREs).  See re_format(7) for more information on regular expressions.  fgrep is quicker than
             both grep and egrep, but can only handle fixed patterns (i.e., it does not interpret regular expressions).  Patterns may consist of one or more lines, allowing any of the pattern lines to match a portion of the
             input.
        """
        let client = EnvironmentClient(configuration: Configuration(endpoint: endpoint, apiKey: key, model: modelName))
        let model = TranslatorModel(settings: AppSettings(), client: client)
        model.prefill(text)

        let deadline = Date().addingTimeInterval(60)
        while model.isTranslating, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.segments.map(\.lines), [0...0, 1...2, 4...6])
        XCTAssertTrue(model.segments.allSatisfy { $0.state == .done && !$0.text.isEmpty })
        XCTAssertFalse(model.output.contains("<s"))
    }
}
