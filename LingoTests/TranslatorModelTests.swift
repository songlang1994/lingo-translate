import XCTest
@testable import Lingo_Translate

@MainActor
private final class ScriptedClient: TranslationClient {
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
final class TranslatorModelTests: XCTestCase {
    private let man = """
    DESCRIPTION
         The grep utility searches any given input files, selecting lines that match one or more patterns.
         line without its trailing newline.  An empty expression matches every line.

         grep is used for simple patterns and basic regular expressions (BREs); egrep can handle
         both grep and egrep, but can only handle fixed patterns (i.e., it does not interpret regular expressions).
         input.
    """

    private func translate(_ text: String, client: ScriptedClient) async -> TranslatorModel {
        let model = TranslatorModel(settings: AppSettings(), client: client)
        model.prefill(text)
        let deadline = Date().addingTimeInterval(5)
        while model.isTranslating, Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertFalse(model.isTranslating)
        return model
    }

    func testMainRequestProducesAlignedSegments() async {
        let client = ScriptedClient([.reply("""
        <s lines="1">描述</s>
        <s lines="2-3">甲</s>
        <s lines="5-7">乙</s>
        """)])
        let model = await translate(man, client: client)

        XCTAssertEqual(client.requests.count, 1)
        XCTAssertTrue(client.requests[0].input.hasPrefix("1| DESCRIPTION\n2|      The grep"))
        XCTAssertEqual(model.segments.map(\.lines), [0...0, 1...2, 4...6])
        XCTAssertEqual(model.segments.map(\.state), [.done, .done, .done])
        XCTAssertEqual(model.output, "描述\n甲\n\n乙")
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.canCopy)
    }

    func testMissingLinesAreRetriedWithOriginalNumbers() async {
        let client = ScriptedClient([
            .reply("<s lines=\"1\">描述</s>\n<s lines=\"2-3\">甲</s>"),
            .reply("<s lines=\"5-7\">乙</s>"),
        ])
        let model = await translate(man, client: client)

        XCTAssertEqual(client.requests.count, 2)
        XCTAssertTrue(client.requests[1].input.hasPrefix("5|      grep is used"))
        XCTAssertTrue(client.requests[1].input.contains("\n7|      input."))
        XCTAssertFalse(client.requests[1].input.contains("1| "))
        XCTAssertEqual(model.segments.map(\.lines), [0...0, 1...2, 4...6])
        XCTAssertEqual(model.segments.map(\.text), ["描述", "甲", "乙"])
    }

    func testLinesStillMissingAfterRetryAreMarkedFailed() async {
        let client = ScriptedClient([
            .reply("<s lines=\"1\">描述</s>"),
            .reply("<s lines=\"2-3\">甲</s>"),
        ])
        let model = await translate(man, client: client)

        XCTAssertEqual(model.segments.map(\.lines), [0...0, 1...2, 4...6])
        XCTAssertEqual(model.segments.map(\.state), [.done, .done, .failed])
        XCTAssertEqual(model.output, "描述\n甲")
        XCTAssertNil(model.errorMessage)
    }

    func testRetryFailureKeepsSegmentsWithoutError() async {
        let client = ScriptedClient([
            .reply("<s lines=\"1-3\">甲</s>"),
            .failure(URLError(.timedOut)),
        ])
        let model = await translate(man, client: client)

        XCTAssertEqual(model.segments.map(\.state), [.done, .failed])
        XCTAssertNil(model.errorMessage)
    }

    func testUntaggedReplyFallsBackToSegmentIDs() async {
        let client = ScriptedClient([
            .reply("描述\n甲\n乙"),
            .reply("<s id=\"2\">甲</s>\n<s id=\"1\">描述</s>\n<s id=\"3\">乙</s>"),
        ])
        let model = await translate(man, client: client)

        XCTAssertEqual(client.requests.count, 2)
        XCTAssertTrue(client.requests[1].instructions.contains("<s id=\"N\">"))
        XCTAssertTrue(client.requests[1].input.hasPrefix("<s id=\"1\">DESCRIPTION</s>\n<s id=\"2\">The grep utility"))
        XCTAssertEqual(model.segments.map(\.lines), [0...0, 1...2, 4...6])
        XCTAssertEqual(model.segments.map(\.text), ["描述", "甲", "乙"])
    }

    func testLongUntaggedReplyIsAbandonedEarly() async {
        let long = String(repeating: "这是没有标签的译文。", count: 200)
        let client = ScriptedClient([
            .reply(long),
            .reply("<s id=\"1\">描述</s>\n<s id=\"2\">甲</s>\n<s id=\"3\">乙</s>"),
        ])
        let model = await translate(man, client: client)

        XCTAssertLessThanOrEqual(client.delivered[0], TranslatorModel.maximumUntaggedReply + 7)
        XCTAssertEqual(model.segments.map(\.text), ["描述", "甲", "乙"])
    }

    func testFallbackWithoutTagsShowsWholeReply() async {
        let client = ScriptedClient([.reply("描述 甲 乙"), .reply("描述\n甲\n乙")])
        let model = await translate(man, client: client)

        XCTAssertEqual(model.segments.map(\.lines), [0...6])
        XCTAssertEqual(model.output, "描述\n甲\n乙")
    }

    func testMainFailureShowsError() async {
        let client = ScriptedClient([.failure(URLError(.timedOut))])
        let model = await translate(man, client: client)

        XCTAssertTrue(model.segments.isEmpty)
        XCTAssertEqual(model.errorMessage, "The request timed out.")
    }

    func testEditingKeepsTheRunningRequestStreamingAndMarksTheOutputStale() async {
        let client = ScriptedClient([.reply("<s lines=\"1\">描述</s>\n" + String(repeating: "<s lines=\"2\">甲</s>\n", count: 50))])
        let model = TranslatorModel(settings: AppSettings(), client: client)
        model.prefill(man)
        while model.segments.isEmpty {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        model.updateInput(man + "\nmore")

        // Editing must not interrupt the request...
        XCTAssertTrue(model.isTranslating)
        XCTAssertFalse(model.isOutputCurrent)
        let delivered = client.deliveredCharacters
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertGreaterThan(client.deliveredCharacters, delivered)

        // ...and the finished translation is kept for the text it was made from.
        let deadline = Date().addingTimeInterval(5)
        while model.isTranslating, Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertFalse(model.isTranslating)
        XCTAssertFalse(model.segments.isEmpty)
        XCTAssertFalse(model.isOutputCurrent)
    }

    func testEditingDoesNotTranslateOnItsOwn() async {
        let client = ScriptedClient([.reply("<s lines=\"1\">你好。</s>")])
        let model = TranslatorModel(settings: AppSettings(), client: client)

        model.updateInput("Hello.")
        try? await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertFalse(model.isTranslating)
        XCTAssertFalse(model.isOutputCurrent)
        XCTAssertFalse(model.isSourceEmpty)
    }

    func testClearingResetsBothColumnsAndFocusesTheSource() async {
        let client = ScriptedClient([.reply("<s lines=\"1\">你好。</s>")])
        let model = await translate("Hello.", client: client)
        let focus = model.focusToken

        model.clear()

        XCTAssertEqual(model.input, "")
        XCTAssertTrue(model.segments.isEmpty)
        XCTAssertEqual(model.output, "")
        XCTAssertFalse(model.isTranslating)
        XCTAssertFalse(model.isOutputCurrent)
        XCTAssertEqual(model.focusToken, focus + 1)
    }

    func testHighlightFollowsItsLinesWhenRetriedSegmentsAreInserted() async {
        let client = ScriptedClient([
            .reply("<s lines=\"1\">描述</s>\n<s lines=\"5-7\">乙</s>"),
            .delayedReply("<s lines=\"2-3\">甲</s>", nanoseconds: 200_000_000),
        ])
        let model = TranslatorModel(settings: AppSettings(), client: client)
        model.prefill(man)
        while client.requests.count < 2 {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        model.highlightSegment(at: 1)
        while model.isTranslating {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        XCTAssertEqual(model.segments.map(\.lines), [0...0, 1...2, 4...6])
        XCTAssertEqual(model.highlightedSegment, 2)
    }

    func testHighlightingTheSameSegmentAgainClearsIt() async {
        let client = ScriptedClient([
            .reply("<s lines=\"1\">描述</s>\n<s lines=\"2-3\">甲</s>\n<s lines=\"5-7\">乙</s>"),
        ])
        let model = await translate(man, client: client)

        model.highlightSegment(at: 1)
        XCTAssertEqual(model.highlightedSegment, 1)
        model.highlightSegment(at: 1)
        XCTAssertNil(model.highlightedSegment)

        // A different segment replaces rather than toggles the highlight.
        model.highlightSegment(at: 2)
        model.highlightSegment(at: 0)
        XCTAssertEqual(model.highlightedSegment, 0)
    }

    func testPrefillWithTheSameTextKeepsTheCurrentTranslation() async {
        let client = ScriptedClient([.reply("<s lines=\"1\">你好。</s>")])
        let model = await translate("Hello.", client: client)
        model.highlightSegment(at: 0)

        model.prefill("Hello.")

        XCTAssertEqual(client.requests.count, 1)
        XCTAssertFalse(model.isTranslating)
        XCTAssertEqual(model.output, "你好。")
        XCTAssertEqual(model.highlightedSegment, 0)
    }

    func testSwapRightAfterAnEditRetranslatesInsteadOfUsingStaleSegments() async {
        let client = ScriptedClient([.reply("<s lines=\"1\">你好。</s>"), .reply("<s lines=\"1\">x</s>")])
        let model = await translate("Hello.", client: client)
        XCTAssertTrue(model.canCopy)

        model.updateInput("Hello. How are you?")
        XCTAssertFalse(model.canCopy)

        let settings = AppSettings()
        let (source, target) = (settings.sourceCode, settings.targetCode)
        defer { settings.sourceCode = source; settings.targetCode = target }
        model.swapLanguages()

        XCTAssertEqual(model.input, "Hello. How are you?")
        XCTAssertTrue(model.isTranslating)
        model.stopTranslation()
    }

    // MARK: - Pure logic

    func testJoinedOutputUsesBlankLineOnlyWhereSourceHasOne() {
        let lines = ["a", "b", "", "c", "d"]
        let segments = [
            TranslationSegment(lines: 0...0, text: "A", state: .done),
            TranslationSegment(lines: 1...1, text: "B1\nB2", state: .done),
            TranslationSegment(lines: 3...3, text: "C", state: .failed),
            TranslationSegment(lines: 4...4, text: "D", state: .done),
        ]
        let joined = TranslatorModel.joinedOutput(segments, lines: lines)
        XCTAssertEqual(joined.text, "A\nB1\nB2\n\nD")
        XCTAssertEqual(joined.ranges, [0...0, 1...2, 4...4])
    }

    func testSwapBuildsSegmentsFromKnownMapping() {
        let lines = ["DESCRIPTION", "     The grep utility searches any given input files, selecting lines that", "     match one or more patterns.", "", "Next."]
        let segments = [
            TranslationSegment(lines: 0...0, text: "描述", state: .done),
            TranslationSegment(lines: 1...2, text: "grep 工具搜索\n输入文件。", state: .done),
            TranslationSegment(lines: 4...4, text: "下一个。", state: .done),
        ]
        let swapped = TranslatorModel.swapped(segments, lines: lines)

        XCTAssertEqual(swapped.input, "描述\ngrep 工具搜索\n输入文件。\n\n下一个。")
        XCTAssertEqual(swapped.segments.map(\.lines), [0...0, 1...2, 4...4])
        XCTAssertEqual(swapped.segments.map(\.text), [
            "DESCRIPTION",
            "The grep utility searches any given input files, selecting lines that match one or more patterns.",
            "Next.",
        ])
    }
}
