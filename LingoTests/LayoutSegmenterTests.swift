import XCTest
@testable import Lingo_Translate

final class LayoutSegmenterTests: XCTestCase {
    private func ranges(_ text: String) -> [ClosedRange<Int>] {
        LayoutSegmenter.segments(of: TextLines.split(text)).map(\.lines)
    }

    func testManDescription() {
        let text = """
        DESCRIPTION
             The grep utility searches any given input files, selecting lines that match one or more patterns.  By default, a pattern matches an input line if the regular expression (RE) in the pattern matches the input
             line without its trailing newline.  An empty expression matches every line.  Each input line that matches at least one of the patterns is written to the standard output.

             grep is used for simple patterns and basic regular expressions (BREs); egrep can handle extended regular expressions (EREs).  See re_format(7) for more information on regular expressions.  fgrep is quicker than
             both grep and egrep, but can only handle fixed patterns (i.e., it does not interpret regular expressions).  Patterns may consist of one or more lines, allowing any of the pattern lines to match a portion of the
             input.
        """
        XCTAssertEqual(ranges(text), [0...0, 1...2, 4...6])
    }

    func testManOptionsWithHangingIndent() {
        let text = """
             -A num, --after-context=num
                     Print num lines of trailing context after each match.  See also the -B and -C
                     options.
             -a, --text
                     Treat all files as ASCII text.
        """
        XCTAssertEqual(ranges(text), [0...0, 1...2, 3...3, 4...4])
    }

    func testMarkdown() {
        let text = """
        ## Install
        Run the installer and follow the prompts. The installer
        checks your system first.
        - Download the package from the
          release page
        - Verify the checksum
        ```
        make install
        ```
        """
        let segments = LayoutSegmenter.segments(of: TextLines.split(text))
        XCTAssertEqual(segments.map(\.lines), [0...0, 1...2, 3...4, 5...5, 6...8])
        XCTAssertEqual(segments.map(\.kind), [.text, .text, .text, .text, .verbatim])
        XCTAssertEqual(segments[2].text, "- Download the package from the release page")
        XCTAssertEqual(segments[4].text, "```\nmake install\n```")
    }

    func testEmailWrappedAt72Columns() {
        let text = """
        Thanks for the report. I looked into it and the crash happens when the
        config file is missing, because we never check the return value of the
        loader.
        Fixed in the next release.
        Cheers.
        """
        XCTAssertEqual(ranges(text), [0...2, 3...3, 4...4])
    }

    func testChineseHardWrapsJoinWithoutSpace() {
        let text = """
        大语言模型在翻译任务中的表现已经接近专业译者的水平，但在处理排版
        混乱的输入时，仍然容易出现段落错位的问题。
        本文提出一种客户端分段方法。
        """
        let segments = LayoutSegmenter.segments(of: TextLines.split(text))
        XCTAssertEqual(segments.map(\.lines), [0...1, 2...2])
        XCTAssertEqual(segments[0].text, "大语言模型在翻译任务中的表现已经接近专业译者的水平，但在处理排版混乱的输入时，仍然容易出现段落错位的问题。")
    }

    func testShortPoemLinesStaySeparate() {
        XCTAssertEqual(ranges("Roses are red\nViolets are blue\nSugar is sweet"), [0...0, 1...1, 2...2])
    }

    func testFirstLineIndent() {
        let text = """
            It was a dark and stormy night; the rain fell in torrents, except at
        occasional intervals, when it was checked by a violent gust of wind.
            The next paragraph starts here.
        """
        XCTAssertEqual(ranges(text), [0...1, 2...2])
    }

    func testWrappedSentence() {
        let text = """
        The original version of this utility was written in the late seventies by
        Ken Thompson at Bell Labs, and it has been rewritten many times since then.
        """
        XCTAssertEqual(ranges(text), [0...1])
    }

    func testCommands() {
        XCTAssertEqual(ranges("ls -la\ncd build\nmake install"), [0...0, 1...1, 2...2])
    }

    func testJoinedTextKeepsRuleSegmentsOnSeparateLines() {
        let lines = ["## Title", "first line of a long paragraph that keeps going and going on,", "second line.", "", "Next."]
        XCTAssertEqual(
            LayoutSegmenter.joinedText(of: lines, in: 0...4),
            "## Title\nfirst line of a long paragraph that keeps going and going on, second line.\n\nNext."
        )
        XCTAssertEqual(LayoutSegmenter.joinedText(of: ["co-", "operate"], in: 0...1), "co-operate")
    }
}
