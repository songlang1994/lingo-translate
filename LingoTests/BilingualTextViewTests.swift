import XCTest
@testable import Lingo_Translate

final class AlignmentPaddingTests: XCTestCase {
    func testNoSegments() {
        let pads = alignmentPadding(left: [], right: [])
        XCTAssertEqual(pads.left, [])
        XCTAssertEqual(pads.right, [])
    }

    func testSingleSegment() {
        let pads = alignmentPadding(left: [10], right: [4])
        XCTAssertEqual(pads.left, [0])
        XCTAssertEqual(pads.right, [6])
    }

    func testOneSideTaller() {
        // Left paragraphs are taller, so the right side is pushed down each time.
        let pads = alignmentPadding(left: [0, 60, 120], right: [0, 20, 40])
        XCTAssertEqual(pads.left, [0, 0, 0])
        XCTAssertEqual(pads.right, [0, 40, 40])
    }

    func testAlternatingTallerSide() {
        let pads = alignmentPadding(left: [0, 60, 80], right: [0, 20, 100])
        XCTAssertEqual(pads.left, [0, 0, 60])
        XCTAssertEqual(pads.right, [0, 40, 0])
    }
}

@MainActor
final class BilingualTextViewTests: XCTestCase {
    private let man = """
    DESCRIPTION
         The grep utility searches any given input files, selecting lines that match one or more patterns.  By default, a pattern matches an input line if the regular expression (RE) in the pattern matches the input
         line without its trailing newline.  An empty expression matches every line.  Each input line that matches at least one of the patterns is written to the standard output.

         grep is used for simple patterns and basic regular expressions (BREs); egrep can handle extended regular expressions (EREs).  See re_format(7) for more information on regular expressions.  fgrep is quicker than
         both grep and egrep, but can only handle fixed patterns (i.e., it does not interpret regular expressions).  Patterns may consist of one or more lines, allowing any of the pattern lines to match a portion of the
         input.
    """

    private let segments = [
        TranslationSegment(lines: 0...0, text: "描述", state: .done),
        TranslationSegment(lines: 1...2, text: "grep 实用程序搜索任何给定的输入文件，选择与一个或多个模式匹配的行。", state: .done),
        TranslationSegment(lines: 4...6, text: "grep 用于简单模式和基本正则表达式（BRE）；egrep 可以处理扩展正则表达式（ERE）。有关正则表达式的更多信息，请参阅 re_format(7)。fgrep 比 grep 和 egrep 都快，但只能处理固定模式。", state: .done),
    ]

    private func makeView(width: CGFloat, segments: [TranslationSegment]) -> BilingualScrollView {
        let view = BilingualScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 400))
        view.update(input: man, segments: segments, highlightedSegment: nil, isTranslating: false, focusToken: 0)
        return view
    }

    private func assertAligned(_ view: BilingualScrollView, count: Int, file: StaticString = #filePath, line: UInt = #line) {
        let tops = view.measuredSegmentTops()
        XCTAssertEqual(tops.count, count, file: file, line: line)
        for top in tops {
            XCTAssertEqual(top.source, top.translation, accuracy: 0.5, "segment \(top.segment)", file: file, line: line)
        }
        XCTAssertEqual(tops.map(\.source), tops.map(\.source).sorted(), file: file, line: line)
    }

    func testSegmentsStartAtTheSameHeightInBothColumns() {
        let view = makeView(width: 640, segments: segments)
        assertAligned(view, count: 3)
    }

    func testAlignmentFollowsWidthAndTextChanges() {
        let view = makeView(width: 640, segments: segments)
        view.setFrameSize(NSSize(width: 980, height: 400))
        assertAligned(view, count: 3)

        var longer = segments
        longer[0].text = String(repeating: "很长的标题译文。", count: 30)
        view.update(input: man, segments: longer, highlightedSegment: nil, isTranslating: false, focusToken: 0)
        assertAligned(view, count: 3)
        let tops = view.measuredSegmentTops()
        XCTAssertGreaterThan(tops[1].source, tops[0].source + 40)
    }

    func testStaleSegmentsBeyondTheTextAreSkipped() {
        let view = makeView(width: 640, segments: segments)
        view.update(input: "DESCRIPTION\nshort", segments: segments, highlightedSegment: nil, isTranslating: false, focusToken: 0)
        assertAligned(view, count: 2)
    }
}

@MainActor
final class BilingualTextViewInteractionTests: XCTestCase {
    private let lines = [
        "DESCRIPTION",
        "     The grep utility searches any given input files, selecting lines that match one or more patterns.",
        "     line without its trailing newline.  An empty expression matches every line.",
        "",
        "     grep is used for simple patterns and basic regular expressions (BREs).",
    ]

    private let segments = [
        TranslationSegment(lines: 0...0, text: "描述", state: .done),
        TranslationSegment(lines: 1...2, text: "grep 工具搜索任何给定的输入文件。", state: .done),
        TranslationSegment(lines: 4...4, text: "grep 用于简单模式。", state: .done),
    ]

    private func makeView() -> (BilingualScrollView, NSWindow) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
        let view = BilingualScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 300))
        window.contentView = view
        view.update(input: lines.joined(separator: "\n"), segments: segments, highlightedSegment: nil, isTranslating: false, focusToken: 0)
        view.layoutSubtreeIfNeeded()
        return (view, window)
    }

    /// A point in the middle of a source line, in the source view's coordinates.
    private func sourcePoint(line: Int, in view: BilingualScrollView) -> NSPoint {
        let string = view.sourceView.string as NSString
        let range = TextLines.ranges(in: string)[line]
        let top = view.sourceView.lineTop(at: range.location) ?? 0
        return NSPoint(x: 20, y: top + 8)
    }

    func testClicksSelectSegmentBandsAndBlankLinesClear() {
        let (view, _) = makeView()

        XCTAssertEqual(view.segmentIndex(at: sourcePoint(line: 0, in: view), inSource: true), 0)
        XCTAssertEqual(view.segmentIndex(at: sourcePoint(line: 2, in: view), inSource: true), 1)
        XCTAssertNil(view.segmentIndex(at: sourcePoint(line: 3, in: view), inSource: true))
        XCTAssertEqual(view.segmentIndex(at: sourcePoint(line: 4, in: view), inSource: true), 2)

        // The translation column shares the same bands.
        XCTAssertEqual(view.segmentIndex(at: sourcePoint(line: 2, in: view), inSource: false), 1)
        XCTAssertNil(view.segmentIndex(at: NSPoint(x: 20, y: view.sourceView.bounds.maxY + 10), inSource: false))
    }

    func testSelectionStartClearsTheHighlightBeforeTheDragEnds() {
        let (view, _) = makeView()
        var cleared = 0
        view.onSelectSegment = { index in
            if index == nil { cleared += 1 }
        }
        view.update(input: lines.joined(separator: "\n"), segments: segments, highlightedSegment: 1, isTranslating: false, focusToken: 0)
        view.layoutSubtreeIfNeeded()
        XCTAssertNotNil(view.sourceView.highlightRange)
        XCTAssertNotNil(view.translationView.highlightRange)

        // Mid-drag: the selection is still growing, and the highlight is
        // already gone from both columns.
        view.sourceView.setSelectedRanges([NSValue(range: NSRange(location: 0, length: 5))], affinity: .downstream, stillSelecting: true)
        XCTAssertNil(view.sourceView.highlightRange)
        XCTAssertNil(view.translationView.highlightRange)
        XCTAssertEqual(cleared, 1)

        // A plain caret move is not a text selection.
        view.sourceView.setSelectedRanges([NSValue(range: NSRange(location: 3, length: 0))], affinity: .downstream, stillSelecting: false)
        XCTAssertEqual(cleared, 1)

        // Selecting translation text clears it as well.
        view.update(input: lines.joined(separator: "\n"), segments: segments, highlightedSegment: 2, isTranslating: false, focusToken: 0)
        XCTAssertNotNil(view.translationView.highlightRange)
        view.translationView.setSelectedRanges([NSValue(range: NSRange(location: 0, length: 2))], affinity: .downstream, stillSelecting: true)
        XCTAssertNil(view.sourceView.highlightRange)
        XCTAssertNil(view.translationView.highlightRange)
        XCTAssertEqual(cleared, 2)
    }

    func testSelectingInOneColumnClearsTheOtherColumnsSelection() {
        let (view, _) = makeView()

        view.sourceView.setSelectedRanges([NSValue(range: NSRange(location: 0, length: 4))], affinity: .downstream, stillSelecting: true)
        XCTAssertEqual(view.sourceView.selectedRange().length, 4)

        view.translationView.setSelectedRanges([NSValue(range: NSRange(location: 0, length: 2))], affinity: .downstream, stillSelecting: true)
        XCTAssertEqual(view.translationView.selectedRange().length, 2)
        XCTAssertEqual(view.sourceView.selectedRange().length, 0)

        // A plain caret move in the source also drops the translation selection.
        view.sourceView.setSelectedRanges([NSValue(range: NSRange(location: 1, length: 0))], affinity: .downstream, stillSelecting: false)
        XCTAssertEqual(view.translationView.selectedRange().length, 0)
        XCTAssertEqual(view.sourceView.selectedRange().location, 1)
    }

    func testHighlightPadsTheTextColumnHorizontally() throws {
        let (view, _) = makeView()
        view.update(input: lines.joined(separator: "\n"), segments: segments, highlightedSegment: 1, isTranslating: false, focusToken: 0)

        let textView = view.sourceView
        let range = try XCTUnwrap(textView.highlightRange)
        let rect = try XCTUnwrap(textView.highlightBounds(for: range))
        let container = try XCTUnwrap(textView.textContainer)
        let padding = BilingualScrollView.highlightInset.width

        XCTAssertGreaterThan(padding, 0)
        XCTAssertEqual(rect.minX, 0, accuracy: 0.5)
        XCTAssertEqual(rect.width, textView.bounds.width, accuracy: 0.5)
        // The band is the text column plus the padding on both sides.
        XCTAssertEqual(rect.width, container.size.width + padding * 2, accuracy: 0.5)
        XCTAssertEqual(textView.textContainerOrigin.x, padding, accuracy: 0.5)
    }

    func testHighlightKeepsTextOutOfThePadding() throws {
        let (view, _) = makeView()
        view.update(input: lines.joined(separator: "\n"), segments: segments, highlightedSegment: 1, isTranslating: false, focusToken: 0)

        let textView = view.sourceView
        let container = try XCTUnwrap(textView.textContainer)
        // Wrapping is unchanged by the padding: the text column is as wide as
        // it was before the band grew into the gutters.
        XCTAssertEqual(container.size.width, view.bounds.width / 2 - BilingualScrollView.gutter * 2, accuracy: 0.5)
        XCTAssertEqual(textView.frame.minX, BilingualScrollView.gutter - BilingualScrollView.highlightInset.width, accuracy: 0.5)
    }

    func testHighlightIsTheSameHeightOnBothSides() throws {
        let (view, _) = makeView()
        // A wrapped translation spanning more lines than the source makes the
        // right column taller when measured on its own.
        var segments = self.segments
        segments[1].text = String(repeating: "grep 工具搜索任何给定的输入文件，", count: 7)
        view.update(input: lines.joined(separator: "\n"), segments: segments, highlightedSegment: 1, isTranslating: false, focusToken: 0)
        view.layoutSubtreeIfNeeded()

        let sourceRange = try XCTUnwrap(view.sourceView.highlightRange)
        let translationRange = try XCTUnwrap(view.translationView.highlightRange)
        let sourceRect = try XCTUnwrap(view.sourceView.highlightBounds(for: sourceRange))
        let translationRect = try XCTUnwrap(view.translationView.highlightBounds(for: translationRange))

        XCTAssertGreaterThan(try XCTUnwrap(view.translationView.textSpan(for: translationRange)).bottom,
                             try XCTUnwrap(view.sourceView.textSpan(for: sourceRange)).bottom,
                             "the fixture must make the translation span taller than the source span")
        XCTAssertEqual(translationRect.minY, sourceRect.minY, accuracy: 0.5)
        XCTAssertEqual(translationRect.height, sourceRect.height, accuracy: 0.5)
    }

    func testHighlightIsASquareFillingTheColumn() throws {
        let (view, _) = makeView()
        view.update(input: lines.joined(separator: "\n"), segments: segments, highlightedSegment: 1, isTranslating: false, focusToken: 0)
        view.layoutSubtreeIfNeeded()

        let textView = view.sourceView
        let range = try XCTUnwrap(textView.highlightRange)
        let rect = try XCTUnwrap(textView.highlightBounds(for: range))
        let rep = try XCTUnwrap(textView.bitmapImageRepForCachingDisplay(in: textView.bounds))
        textView.cacheDisplay(in: textView.bounds, to: rep)

        let scale = CGFloat(rep.pixelsWide) / textView.bounds.width
        func alpha(x: CGFloat, top: CGFloat) -> CGFloat {
            let px = min(max(Int(x * scale), 0), rep.pixelsWide - 1)
            let py = min(max(Int(top * scale), 0), rep.pixelsHigh - 1)
            return rep.colorAt(x: px, y: py)?.alphaComponent ?? 0
        }

        // The very corner of the band is painted: no rounded corner.
        XCTAssertGreaterThan(alpha(x: 1, top: rect.minY + 1), 0.05)
        // The band reaches both edges of the padded column.
        XCTAssertGreaterThan(alpha(x: 1, top: rect.midY), 0.05)
        XCTAssertGreaterThan(alpha(x: textView.bounds.width - 1, top: rect.midY), 0.05)
        // Above the band nothing is painted.
        XCTAssertLessThan(alpha(x: 1, top: 0.5), 0.05)
    }

    func testPasteReplacingTheWholeSourceRequestsTranslation() throws {
        let (view, window) = makeView()
        var sourceChanges: [String] = []
        var pasteCount = 0
        view.onSourceChange = { sourceChanges.append($0) }
        view.onReplaceAllPaste = { pasteCount += 1 }
        window.makeFirstResponder(view.sourceView)

        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString("pasted text", forType: .string)
        defer {
            pasteboard.clearContents()
            if let saved {
                pasteboard.setString(saved, forType: .string)
            }
        }

        // Pasting into an empty source replaces everything.
        view.update(input: "", segments: [], highlightedSegment: nil, isTranslating: false, focusToken: 0)
        view.sourceView.paste(nil)
        XCTAssertEqual(pasteCount, 1)
        XCTAssertEqual(sourceChanges.last, "pasted text")
        XCTAssertEqual(view.sourceView.string, "pasted text")

        // Pasting inside existing text is an ordinary edit.
        view.sourceView.setSelectedRange(NSRange(location: 3, length: 0))
        view.sourceView.paste(nil)
        XCTAssertEqual(pasteCount, 1)

        // Select All + Paste replaces everything again.
        view.sourceView.selectAll(nil)
        view.sourceView.paste(nil)
        XCTAssertEqual(pasteCount, 2)
    }

    func testStaleTranslationIsDrawnInALighterColor() throws {
        let (view, _) = makeView()
        view.update(input: lines.joined(separator: "\n"), segments: segments, highlightedSegment: nil, isTranslating: false, focusToken: 0)
        let storage = try XCTUnwrap(view.translationView.textStorage)
        let normal = try XCTUnwrap(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        XCTAssertEqual(normal, SegmentTextView.translationAttributes[.foregroundColor] as? NSColor)

        view.update(
            input: lines.joined(separator: "\n") + "\nmore",
            segments: segments,
            highlightedSegment: nil,
            isTranslating: false,
            focusToken: 0,
            isTranslationStale: true
        )
        let stale = try XCTUnwrap(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        XCTAssertEqual(stale, NSColor.secondaryLabelColor)
        XCTAssertNotEqual(stale, normal)
    }

    func testCompositionReachesTheModelOnlyWhenCommitted() {
        let (view, window) = makeView()
        var reported: [String] = []
        view.onSourceChange = { reported.append($0) }
        window.makeFirstResponder(view.sourceView)
        view.sourceView.setSelectedRange(NSRange(location: 0, length: 0))

        view.sourceView.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(reported.isEmpty)

        view.sourceView.insertText("中", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(reported, ["中" + lines.joined(separator: "\n")])
    }

    func testProgrammaticReplacementIsUndoable() throws {
        let (view, window) = makeView()
        window.makeFirstResponder(view.sourceView)
        let undoManager = try XCTUnwrap(view.sourceView.undoManager)
        undoManager.removeAllActions()
        // Group explicitly, as each user action would be its own event.
        undoManager.groupsByEvent = false
        defer { undoManager.groupsByEvent = true }
        let original = view.sourceView.string

        undoManager.beginUndoGrouping()
        view.update(input: "swapped", segments: [], highlightedSegment: nil, isTranslating: false, focusToken: 0)
        undoManager.endUndoGrouping()
        XCTAssertEqual(view.sourceView.string, "swapped")

        undoManager.undo()
        XCTAssertEqual(view.sourceView.string, original)
    }

    func testPrefillThenPanelFocusStillStartsTheTranslationAtTheTop() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
        let view = BilingualScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 300))
        window.contentView = view
        let long = (0..<40).map { "line \($0) of the source text" }.joined(separator: "\n")
        let segments = [TranslationSegment(lines: 0...0, text: "译文 0", state: .streaming)]

        // The panel is built while the prefill translation is already running,
        // then shown and focused, as on launch with selected text.
        view.update(input: long, segments: [], highlightedSegment: nil, isTranslating: true, focusToken: 0)
        view.layoutSubtreeIfNeeded()
        window.makeFirstResponder(view.sourceView)
        view.update(input: long, segments: segments, highlightedSegment: nil, isTranslating: true, focusToken: 1)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.contentView.bounds.minY, 0)
    }

    func testTranslationStartsAtTheTopAndFollowsOnlyAfterTheUserScrollsDown() {
        let (view, _) = makeView()
        let long = (0..<40).map { "line \($0) of the source text" }
        var streamed: [TranslationSegment] = []

        // A long source leaves the view scrolled to the bottom, as it is after
        // a paste puts the caret at the end.
        view.update(input: long.joined(separator: "\n"), segments: [], highlightedSegment: nil, isTranslating: false, focusToken: 0)
        view.layoutSubtreeIfNeeded()
        let startLimit = (view.documentView?.frame.height ?? 0) - view.contentView.bounds.height
        view.contentView.scroll(to: NSPoint(x: 0, y: startLimit))
        view.reflectScrolledClipView(view.contentView)
        XCTAssertGreaterThan(view.contentView.bounds.minY, 0)

        func stream(upTo count: Int) {
            while streamed.count < count {
                streamed.append(TranslationSegment(lines: streamed.count...streamed.count, text: "译文 \(streamed.count)", state: .done))
            }
            view.update(input: long.joined(separator: "\n"), segments: streamed, highlightedSegment: nil, isTranslating: true, focusToken: 0)
            view.layoutSubtreeIfNeeded()
        }
        func isAtBottom() -> Bool {
            let clip = view.contentView
            return abs(clip.bounds.maxY - (view.documentView?.frame.height ?? 0)) < 1
        }

        // Starting the translation returns to the top so the streamed output
        // is visible from its first line.
        stream(upTo: 1)
        XCTAssertEqual(view.contentView.bounds.minY, 0)

        // Streaming does not drag the view to the bottom on its own.
        stream(upTo: 20)
        XCTAssertEqual(view.contentView.bounds.minY, 0)

        // Back near the bottom: following resumes.
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: view)
        let limit = (view.documentView?.frame.height ?? 0) - view.contentView.bounds.height
        view.contentView.scroll(to: NSPoint(x: 0, y: limit - 10))
        view.reflectScrolledClipView(view.contentView)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: view)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        stream(upTo: 30)
        XCTAssertTrue(isAtBottom())

        // Restarting the translation clears the output and returns to the top.
        view.update(input: long.joined(separator: "\n"), segments: [], highlightedSegment: nil, isTranslating: true, focusToken: 0)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.contentView.bounds.minY, 0)
    }
}

@MainActor
final class SourceFontTests: XCTestCase {
    func testLatinTextKeepsTheSystemFontAfterReplacingCJKText() throws {
        let view = BilingualScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 300))
        view.update(input: "中文原文", segments: [], highlightedSegment: nil, isTranslating: false, focusToken: 0)
        view.layoutSubtreeIfNeeded()
        view.update(input: "--basic-regexp", segments: [], highlightedSegment: nil, isTranslating: false, focusToken: 0)

        let storage = try XCTUnwrap(view.sourceView.textStorage)
        let font = try XCTUnwrap(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(font.fontName, SegmentTextView.font.fontName)
    }

    func testFixedLineHeightAndZeroSpacingInBothColumns() throws {
        let view = BilingualScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 300))
        let segments = [
            TranslationSegment(lines: 0...1, text: "First line\n第二行", state: .done),
        ]
        view.update(input: "First line\n第二行", segments: segments, highlightedSegment: nil, isTranslating: false, focusToken: 0)
        view.layoutSubtreeIfNeeded()

        for textView in [view.sourceView, view.translationView] {
            let storage = try XCTUnwrap(textView.textStorage)
            let style = try XCTUnwrap(storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            XCTAssertEqual(style.minimumLineHeight, 32)
            XCTAssertEqual(style.maximumLineHeight, 32)
            XCTAssertEqual(style.lineSpacing, 0)
            XCTAssertEqual(style.paragraphSpacing, 0)

            let manager = try XCTUnwrap(textView.layoutManager)
            var lineHeights: [CGFloat] = []
            var baselineOffsets: [CGFloat] = []
            manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { rect, _, _, glyphRange, _ in
                lineHeights.append(rect.height)
                baselineOffsets.append(manager.location(forGlyphAt: glyphRange.location).y)
            }
            XCTAssertEqual(lineHeights, [32, 32])
            XCTAssertEqual(baselineOffsets, [22, 22])
        }
    }
}
