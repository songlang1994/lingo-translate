import XCTest
@testable import Lingo_Translate

final class SegmentParserTests: XCTestCase {
    private let manLines = TextLines.split("""
    DESCRIPTION
         The grep utility searches any given input files, selecting lines that match one or more patterns.
         line without its trailing newline.  An empty expression matches every line.

         grep is used for simple patterns and basic regular expressions (BREs); egrep can handle
         both grep and egrep, but can only handle fixed patterns (i.e., it does not interpret regular expressions).
         input.
    """)

    private let manReply = """
    <s lines="1">描述</s>
    <s lines="2-3">grep 工具搜索任何给定的输入文件。空表达式匹配每一行。</s>
    <s lines="5-7">grep 用于简单模式和基本正则表达式。</s>
    """

    private func parse(
        _ text: String,
        lines: [String]? = nil,
        allowed: IndexSet? = nil,
        isFinal: Bool = true
    ) -> SegmentParseResult {
        let lines = lines ?? manLines
        let mode = SegmentParser.Mode.lineRanges(allowedLines: allowed ?? IndexSet(integersIn: lines.indices))
        return SegmentParser.parse(text, mode: mode, lines: lines, isFinal: isFinal)
    }

    func testBasicRangesAreConvertedToZeroBased() {
        let result = parse(manReply)
        XCTAssertTrue(result.foundAnyTag)
        XCTAssertEqual(result.segments.map(\.lines), [0...0, 1...2, 4...6])
        XCTAssertEqual(result.segments[0].text, "描述")
        XCTAssertTrue(result.segments.allSatisfy(\.isComplete))
        XCTAssertTrue(SegmentParser.missingLines(in: result.segments.map(\.lines), lines: manLines).isEmpty)
    }

    func testEnDashRangeAndSpaces() {
        let result = parse(#"<s lines=" 2 – 3 ">x</s>"#)
        XCTAssertEqual(result.segments.map(\.lines), [1...2])
    }

    func testStreamingPrefixesNeverShowPartialTags() {
        let final = parse(manReply).segments
        let characters = Array(manReply)
        var previousCount = 0

        for length in 0...characters.count {
            let prefix = String(characters[..<length])
            let segments = parse(prefix, isFinal: false).segments

            XCTAssertGreaterThanOrEqual(segments.count, previousCount, "prefix: \(prefix)")
            previousCount = segments.count

            for (index, segment) in segments.enumerated() {
                XCTAssertEqual(segment.lines, final[index].lines)
                XCTAssertTrue(final[index].text.hasPrefix(segment.text), "\(segment.text) at prefix \(prefix)")
                XCTAssertFalse(segment.text.contains("<"), "prefix: \(prefix)")
            }
            for segment in segments.dropLast() {
                XCTAssertTrue(segment.isComplete)
            }
        }
    }

    func testLastSegmentIsCompleteOnlyAfterCloseTagOrFinal() {
        XCTAssertFalse(parse(#"<s lines="1">描述"#, isFinal: false).segments[0].isComplete)
        XCTAssertTrue(parse(#"<s lines="1">描述</s>"#, isFinal: false).segments[0].isComplete)
        XCTAssertTrue(parse(#"<s lines="1">描述"#, isFinal: true).segments[0].isComplete)
    }

    func testMissingCloseTagPreambleFenceAndIndentedTag() {
        let reply = """
        Here is the translation:
        ```
          <s lines="1">描述
        <s lines="2-3">甲</s>
        \t<s lines="5-7">乙</s>
        ```
        """
        let result = parse(reply)
        XCTAssertEqual(result.segments.map(\.lines), [0...0, 1...2, 4...6])
        XCTAssertEqual(result.segments.map(\.text), ["描述", "甲", "乙"])
    }

    func testTagsOnOneLineAfterCloseTag() {
        let result = parse(#"<s lines="1">A</s><s lines="2-3">B</s>"#)
        XCTAssertEqual(result.segments.map(\.lines), [0...0, 1...2])
        XCTAssertEqual(result.segments.map(\.text), ["A", "B"])
    }

    func testOverlapReversedOutOfRangeAndDuplicateTags() {
        let reply = """
        <s lines="1-2">A</s>
        <s lines="2-3">B</s>
        <s lines="3">C</s>
        <s lines="6-5">D</s>
        <s lines="7-20">E</s>
        <s lines="30-40">F</s>
        <s lines="7">G</s>
        """
        let result = parse(reply)
        XCTAssertEqual(result.segments.map(\.lines), [0...1, 2...2, 5...5, 6...6])
        XCTAssertEqual(result.segments.map(\.text), ["A", "B\nC", "D", "E\nG"])
    }

    func testMissingLinesSkipBlankLinesAndAllowBlankLinesInsideRanges() {
        let lines = ["a", "b", "", "c", "", "d"]
        let result = parse(#"<s lines="1">A</s>\#n<s lines="2-4">B</s>"#, lines: lines)
        XCTAssertEqual(result.segments.map(\.lines), [0...0, 1...3])
        XCTAssertEqual(SegmentParser.missingLines(in: result.segments.map(\.lines), lines: lines), IndexSet([5]))

        let skipped = parse(#"<s lines="1">A</s>\#n<s lines="6">D</s>"#, lines: lines)
        XCTAssertEqual(SegmentParser.missingLines(in: skipped.segments.map(\.lines), lines: lines), IndexSet([1, 3]))
    }

    func testCloseTagInsideTranslationUsesLastOccurrence() {
        let result = parse(#"<s lines="1">价格 <s>100</s> 元</s>```"#, lines: ["Price <s>100</s>"])
        XCTAssertEqual(result.segments.map(\.text), ["价格 <s>100</s> 元"])
    }

    func testRetryModeShrinksRangesToAllowedLines() {
        let lines = (1...10).map { "line \($0)" }
        let allowed = IndexSet([1, 2, 8])
        let reply = """
        <s lines="2-9">A</s>
        <s lines="5">B</s>
        <s lines="9">C</s>
        """
        let result = parse(reply, lines: lines, allowed: allowed)
        XCTAssertEqual(result.segments.map(\.lines), [1...2, 8...8])
        XCTAssertEqual(result.segments.map(\.text), ["A\nB", "C"])
    }

    func testRetryModeKeepsBlankLinesBetweenAllowedLines() {
        let lines = ["a", "b", "", "c"]
        let result = parse(#"<s lines="2-4">X</s>"#, lines: lines, allowed: IndexSet([1, 3]))
        XCTAssertEqual(result.segments.map(\.lines), [1...3])
    }

    func testSegmentIDsMapToRanges() {
        let ranges = [0...0, 1...2, 4...6]
        let reply = """
        <s id="2">B</s>
        <s id="1">A</s>
        <s id="9">X</s>
        <s id="2">Y</s>
        """
        let result = SegmentParser.parse(reply, mode: .segmentIDs(ranges: ranges), lines: manLines, isFinal: true)
        XCTAssertEqual(result.segments.map(\.lines), [0...0, 1...2])
        XCTAssertEqual(result.segments.map(\.text), ["A", "B"])
    }

    func testNoTags() {
        let result = parse("描述\ngrep 工具搜索任何给定的输入文件。")
        XCTAssertFalse(result.foundAnyTag)
        XCTAssertTrue(result.segments.isEmpty)
    }

    func testNumberedInputKeepsIndentationAndOriginalNumbers() {
        let lines = ["DESCRIPTION", "     The grep", "", "\tx"]
        XCTAssertEqual(Prompt.numberedInput(lines: lines), "1| DESCRIPTION\n2|      The grep\n3| \n4| \tx")
        XCTAssertEqual(Prompt.numberedInput(lines: lines, indices: IndexSet([1, 3])), "2|      The grep\n4| \tx")
    }
}

final class TextLinesTests: XCTestCase {
    func testSplitsLikeTextViewParagraphs() {
        XCTAssertEqual(TextLines.split(""), [""])
        XCTAssertEqual(TextLines.split("a"), ["a"])
        XCTAssertEqual(TextLines.split("a\n"), ["a", ""])
        XCTAssertEqual(TextLines.split("a\r\nb\u{2029}c\n\nd"), ["a", "b", "c", "", "d"])
    }
}
