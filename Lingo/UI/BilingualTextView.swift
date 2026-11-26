import AppKit
import SwiftUI

/// Extra space to add above each segment so both columns start it at the same
/// height. `left` and `right` are the natural tops (without padding) of each
/// segment's first line; returns the padding to insert before each anchor.
func alignmentPadding(left: [CGFloat], right: [CGFloat]) -> (left: [CGFloat], right: [CGFloat]) {
    let count = min(left.count, right.count)
    var padLeft: [CGFloat] = []
    var padRight: [CGFloat] = []
    padLeft.reserveCapacity(count)
    padRight.reserveCapacity(count)

    var extraLeft: CGFloat = 0
    var extraRight: CGFloat = 0
    for index in 0..<count {
        let topLeft = left[index] + extraLeft
        let topRight = right[index] + extraRight
        let top = max(topLeft, topRight)
        padLeft.append(top - topLeft)
        padRight.append(top - topRight)
        extraLeft += top - topLeft
        extraRight += top - topRight
    }
    return (padLeft, padRight)
}

/// Source and translation side by side as two TextKit 1 text views. Each
/// segment starts at the same height in both columns; the gap is filled with
/// layout-time paragraph spacing, so neither text is modified.
struct BilingualTextView: NSViewRepresentable {
    @ObservedObject var model: TranslatorModel

    func makeNSView(context: Context) -> BilingualScrollView {
        let view = BilingualScrollView()
        let model = model
        view.onSourceChange = { [weak model] text in
            model?.updateInput(text)
        }
        view.onSelectSegment = { [weak model] index in
            model?.highlightSegment(at: index)
        }
        return view
    }

    func updateNSView(_ view: BilingualScrollView, context: Context) {
        view.update(
            input: model.input,
            segments: model.segments,
            highlightedSegment: model.highlightedSegment,
            isTranslating: model.isTranslating,
            focusToken: model.focusToken
        )
    }
}

final class BilingualScrollView: NSScrollView, NSTextViewDelegate {
    var onSourceChange: ((String) -> Void)?
    var onSelectSegment: ((Int?) -> Void)?

    static let gutter: CGFloat = 14
    static let topPadding: CGFloat = 12
    static let bottomPadding: CGFloat = 14
    /// Room for the rounded highlight around the text, outside the text column.
    static let highlightInset = NSSize(width: 6, height: 3)

    private let document = BilingualDocumentView()
    let sourceView = SegmentTextView.make(editable: true)
    let translationView = SegmentTextView.make(editable: false)
    private let sourcePadding = PaddingLayoutDelegate()
    private let translationPadding = PaddingLayoutDelegate()

    private var segments: [TranslationSegment] = []
    private var translationRanges: [NSRange] = []
    private var highlightedSegment: Int?
    /// Aligned top of each segment that takes part in alignment, in text view coordinates.
    private var bands: [(segment: Int, top: CGFloat)] = []
    private var contentBottom: CGFloat = 0
    private var focusToken: Int?
    private var revealSelectionAfterLayout = false

    // Following the streaming output.
    private let followTolerance: CGFloat = 24
    private var isTranslating = false
    private var isFollowing = true
    private var isLiveScrollTracking = false
    private var observers: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        documentView = document

        document.onLayout = { [weak self] in self?.layoutDocument() }
        document.onMouseDown = { [weak self] in self?.onSelectSegment?(nil) }
        document.addSubview(sourceView)
        document.addSubview(translationView)

        sourceView.delegate = self
        sourceView.layoutManager?.delegate = sourcePadding
        translationView.layoutManager?.delegate = translationPadding
        sourceView.highlightColor = Self.sourceHighlight
        translationView.highlightColor = Self.translationHighlight
        sourceView.placeholder = "Text"

        sourceView.onMouseDown = { [weak self] point in self?.handleClick(at: point, inSource: true) }
        translationView.onMouseDown = { [weak self] point in self?.handleClick(at: point, inSource: false) }

        observeScrolling()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Updates from the model

    func update(
        input: String,
        segments: [TranslationSegment],
        highlightedSegment: Int?,
        isTranslating: Bool,
        focusToken: Int
    ) {
        // Programmatic edits (prefill, swap). Never interrupt an IME composition.
        if sourceView.string != input, !sourceView.hasMarkedText() {
            sourceView.replaceAllText(with: input)
            setNeedsAlignment()
        }

        if segments != self.segments {
            self.segments = segments
            reloadTranslation()
        }

        if highlightedSegment != self.highlightedSegment {
            self.highlightedSegment = highlightedSegment
            updateHighlight()
        }

        if isTranslating != self.isTranslating {
            self.isTranslating = isTranslating
            if isTranslating {
                isFollowing = true
                followToBottom()
            }
        }

        if focusToken != self.focusToken {
            self.focusToken = focusToken
            focusSource()
        }
    }

    private func focusSource() {
        guard let window else {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.focusSource()
            }
            return
        }
        window.makeFirstResponder(sourceView)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        setNeedsAlignment()
    }

    private func reloadTranslation() {
        let text = NSMutableAttributedString()
        var ranges: [NSRange] = []

        for (index, segment) in segments.enumerated() {
            if index > 0 {
                text.append(NSAttributedString(string: "\n", attributes: SegmentTextView.translationAttributes))
            }
            let isFailed = segment.state == .failed
            let content = isFailed ? "Not translated" : segment.text
            let attributes = isFailed ? SegmentTextView.failedAttributes : SegmentTextView.translationAttributes
            ranges.append(NSRange(location: text.length, length: (content as NSString).length))
            text.append(NSAttributedString(string: content, attributes: attributes))
        }

        translationRanges = ranges
        // Keep the selection when only the streaming tail changed.
        let selection = translationView.selectedRange()
        translationView.textStorage?.setAttributedString(text)
        if NSMaxRange(selection) <= text.length {
            translationView.setSelectedRange(selection)
        }
        updateHighlight()
        setNeedsAlignment()
    }

    // MARK: - NSTextViewDelegate

    /// Typing after CJK text would otherwise continue in its fallback font.
    func textView(
        _ textView: NSTextView,
        shouldChangeTypingAttributes oldTypingAttributes: [String: Any] = [:],
        toAttributes newTypingAttributes: [NSAttributedString.Key: Any] = [:]
    ) -> [NSAttributedString.Key: Any] {
        SegmentTextView.sourceAttributes
    }

    func textDidChange(_ notification: Notification) {
        revealSelectionAfterLayout = true
        setNeedsAlignment()
        // Only finished text reaches the model; marked (composing) text waits.
        guard !sourceView.hasMarkedText() else { return }
        onSourceChange?(sourceView.string)
        updateHighlight()
    }

    // MARK: - Layout and alignment

    private func setNeedsAlignment() {
        document.needsLayout = true
    }

    override func tile() {
        super.tile()
        setNeedsAlignment()
    }

    /// Runs once per layout pass: positions both columns, aligns segment tops,
    /// and sizes the document. Padding only changes when the measured layout
    /// changes, so a second pass settles immediately.
    private func layoutDocument() {
        let width = contentView.bounds.width
        guard width > 0 else { return }

        let inset = Self.highlightInset
        let half = (width / 2).rounded(.down)
        let columnWidth = max(half - Self.gutter * 2, 40)
        let viewTop = Self.topPadding - inset.height
        let minimumHeight = max(contentView.bounds.height - Self.topPadding - Self.bottomPadding, 22) + inset.height * 2

        sourceView.setFrameOrigin(NSPoint(x: Self.gutter - inset.width, y: viewTop))
        translationView.setFrameOrigin(NSPoint(x: half + Self.gutter - inset.width, y: viewTop))
        for view in [sourceView, translationView] where view.frame.width != columnWidth + inset.width * 2 {
            view.setFrameSize(NSSize(width: columnWidth + inset.width * 2, height: view.frame.height))
        }

        align()

        var height: CGFloat = 0
        for view in [sourceView, translationView] {
            let viewHeight = max(view.contentHeight + inset.height * 2, minimumHeight)
            if view.frame.height != viewHeight {
                view.setFrameSize(NSSize(width: view.frame.width, height: viewHeight))
            }
            height = max(height, view.contentHeight)
        }
        contentBottom = height

        let documentHeight = max(viewTop + max(sourceView.frame.height, translationView.frame.height) + Self.bottomPadding - inset.height, contentView.bounds.height)
        let size = NSSize(width: width, height: documentHeight.rounded(.up))
        if document.frame.size != size {
            document.setFrameSize(size)
        }

        if revealSelectionAfterLayout {
            revealSelectionAfterLayout = false
            if window?.firstResponder === sourceView {
                sourceView.scrollRangeToVisible(sourceView.selectedRange())
            }
        }
    }

    private func align() {
        guard let sourceManager = sourceView.layoutManager,
              let sourceContainer = sourceView.textContainer,
              let translationManager = translationView.layoutManager,
              let translationContainer = translationView.textContainer else { return }

        let sourceString = sourceView.string as NSString
        let lineRanges = TextLines.ranges(in: sourceString)
        let translationLength = (translationView.string as NSString).length

        // Anchors: first character of the segment's first line on the left and of
        // its translation on the right. Segments outside the edited text are skipped.
        var participants: [(segment: Int, source: Int, translation: Int)] = []
        for (index, segment) in segments.enumerated() where index < translationRanges.count {
            let line = segment.lines.lowerBound
            guard line < lineRanges.count else { continue }
            let sourceAnchor = lineRanges[line].location
            let translationAnchor = translationRanges[index].location
            guard sourceAnchor < sourceString.length, translationAnchor < translationLength else { continue }
            if let last = participants.last, last.source >= sourceAnchor || last.translation >= translationAnchor { continue }
            participants.append((index, sourceAnchor, translationAnchor))
        }

        sourceManager.ensureLayout(for: sourceContainer)
        translationManager.ensureLayout(for: translationContainer)

        let left = Self.naturalTops(of: participants.map(\.source), in: sourceManager, container: sourceContainer)
        let right = Self.naturalTops(of: participants.map(\.translation), in: translationManager, container: translationContainer)
        let pads = alignmentPadding(left: left, right: right)

        var sourcePads: [Int: CGFloat] = [:]
        var translationPads: [Int: CGFloat] = [:]
        var newBands: [(segment: Int, top: CGFloat)] = []
        var extra: CGFloat = 0
        for (index, participant) in participants.enumerated() {
            if pads.left[index] > 0 { sourcePads[participant.source] = pads.left[index] }
            if pads.right[index] > 0 { translationPads[participant.translation] = pads.right[index] }
            extra += pads.left[index]
            newBands.append((participant.segment, left[index] + extra))
        }
        bands = newBands

        let sourceChanged = sourcePadding.apply(sourcePads, to: sourceManager, length: sourceString.length)
        let translationChanged = translationPadding.apply(translationPads, to: translationManager, length: translationLength)
        if sourceChanged {
            sourceManager.ensureLayout(for: sourceContainer)
            sourceView.needsDisplay = true
        }
        if translationChanged {
            translationManager.ensureLayout(for: translationContainer)
            translationView.needsDisplay = true
        }
    }

    /// Tops of the lines starting at the given (ascending) character indexes,
    /// with any spacing already added before them subtracted. Spacing added by
    /// the delegate shows up as the gap between a line fragment and its used rect.
    private static func naturalTops(of anchors: [Int], in manager: NSLayoutManager, container: NSTextContainer) -> [CGFloat] {
        guard !anchors.isEmpty else { return [] }
        let glyphAnchors = anchors.map { manager.glyphIndexForCharacter(at: $0) }
        var tops: [CGFloat] = []
        tops.reserveCapacity(anchors.count)
        var next = 0
        var extra: CGFloat = 0

        let glyphs = NSRange(location: 0, length: manager.numberOfGlyphs)
        manager.enumerateLineFragments(forGlyphRange: glyphs) { rect, usedRect, _, glyphRange, stop in
            extra += usedRect.minY - rect.minY
            while next < glyphAnchors.count, NSLocationInRange(glyphAnchors[next], glyphRange) {
                tops.append(usedRect.minY - extra)
                next += 1
            }
            if next == glyphAnchors.count { stop.pointee = true }
        }
        while tops.count < anchors.count {
            tops.append(tops.last ?? 0)
        }
        return tops
    }

    /// Laid-out top of each segment's first line in both columns, for tests.
    func measuredSegmentTops() -> [(segment: Int, source: CGFloat, translation: CGFloat)] {
        layoutSubtreeIfNeeded()
        let lineRanges = TextLines.ranges(in: sourceView.string as NSString)
        return segments.indices.compactMap { index in
            guard index < translationRanges.count, segments[index].lines.lowerBound < lineRanges.count,
                  let source = sourceView.lineTop(at: lineRanges[segments[index].lines.lowerBound].location),
                  let translation = translationView.lineTop(at: translationRanges[index].location) else { return nil }
            return (index, source + sourceView.frame.minY, translation + translationView.frame.minY)
        }
    }

    // MARK: - Highlight

    private func updateHighlight() {
        guard let index = highlightedSegment, segments.indices.contains(index) else {
            sourceView.highlightRange = nil
            translationView.highlightRange = nil
            return
        }

        let lineRanges = TextLines.ranges(in: sourceView.string as NSString)
        let lines = segments[index].lines
        if lines.lowerBound < lineRanges.count {
            let first = lineRanges[lines.lowerBound]
            let last = lineRanges[min(lines.upperBound, lineRanges.count - 1)]
            sourceView.highlightRange = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        } else {
            sourceView.highlightRange = nil
        }
        translationView.highlightRange = index < translationRanges.count ? translationRanges[index] : nil
    }

    private func handleClick(at point: NSPoint, inSource: Bool) {
        onSelectSegment?(segmentIndex(at: point, inSource: inSource))
    }

    /// Clicks pick the segment whose band (from its aligned top to the next
    /// segment's top) contains the point. Blank source lines and points outside
    /// every band select nothing. `point` is in the clicked text view's coordinates.
    func segmentIndex(at point: NSPoint, inSource: Bool) -> Int? {
        layoutSubtreeIfNeeded()
        if inSource {
            let string = sourceView.string as NSString
            let index = sourceView.characterIndexForInsertion(at: point)
            let lineRanges = TextLines.ranges(in: string)
            if let line = lineRanges.lastIndex(where: { $0.location <= index }),
               TextLines.isBlank(string.substring(with: lineRanges[line])) {
                return nil
            }
        }

        let y = point.y - SegmentTextView.containerOriginY
        guard y <= contentBottom else { return nil }
        return bands.last(where: { $0.top <= y })?.segment
    }

    // MARK: - Following the output

    private func observeScrolling() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: self, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.isLiveScrollTracking = true
                self.isFollowing = false
            },
            center.addObserver(forName: NSScrollView.didLiveScrollNotification, object: self, queue: .main) { [weak self] _ in
                guard let self else { return }
                // Wait for the end of a gesture or thumb drag, otherwise a
                // mid-drag check could re-pin the view and fight the user.
                guard !self.isLiveScrollTracking else { return }
                self.isFollowing = self.isScrolledToBottom()
            },
            center.addObserver(forName: NSScrollView.didEndLiveScrollNotification, object: self, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.isLiveScrollTracking = false
                // Let the scroll view settle before reading its geometry.
                DispatchQueue.main.async {
                    self.isFollowing = self.isScrolledToBottom()
                }
            },
        ]

        document.postsFrameChangedNotifications = true
        observers.append(
            center.addObserver(forName: NSView.frameDidChangeNotification, object: document, queue: .main) { [weak self] _ in
                self?.followToBottom()
            }
        )
    }

    private func followToBottom() {
        guard isFollowing, isTranslating else { return }
        let clipView = contentView
        let target = max(0, document.bounds.height - clipView.bounds.height)
        guard abs(clipView.bounds.origin.y - target) > 0.5 else { return }
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: target))
        reflectScrolledClipView(clipView)
    }

    private func isScrolledToBottom() -> Bool {
        let clipView = contentView
        let limit = max(0, document.bounds.height - clipView.bounds.height)
        return abs(clipView.bounds.origin.y - limit) <= followTolerance
    }

    // MARK: - Colors

    static let sourceHighlight = NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.42, green: 0.62, blue: 1.0, alpha: 0.40)
            : NSColor(srgbRed: 0.62, green: 0.78, blue: 1.0, alpha: 0.45)
    }

    static let translationHighlight = NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 1.0, green: 0.76, blue: 0.87, alpha: 0.58)
            : NSColor(srgbRed: 1.0, green: 0.73, blue: 0.82, alpha: 0.6)
    }
}

/// Returns the spacing chosen by the aligner before the line that starts at a
/// given character, and nothing anywhere else.
private final class PaddingLayoutDelegate: NSObject, NSLayoutManagerDelegate {
    private(set) var pads: [Int: CGFloat] = [:]

    /// Installs new padding and invalidates layout from the first changed
    /// anchor. Returns false when nothing changed.
    func apply(_ newPads: [Int: CGFloat], to manager: NSLayoutManager, length: Int) -> Bool {
        guard newPads != pads else { return false }
        let changed = Set(newPads.keys).union(pads.keys).filter { newPads[$0] != pads[$0] }
        pads = newPads
        guard let first = changed.min(), first < length else { return true }
        manager.invalidateLayout(forCharacterRange: NSRange(location: first, length: length - first), actualCharacterRange: nil)
        return true
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        paragraphSpacingBeforeGlyphAt glyphIndex: Int,
        withProposedLineFragmentRect rect: NSRect
    ) -> CGFloat {
        guard !pads.isEmpty else { return 0 }
        return pads[layoutManager.characterIndexForGlyph(at: glyphIndex)] ?? 0
    }
}

private final class BilingualDocumentView: NSView {
    var onLayout: (() -> Void)?
    var onMouseDown: (() -> Void)?

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        onLayout?()
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }
}

final class SegmentTextView: NSTextView {
    static let font = NSFont.systemFont(ofSize: 17)

    static let translationAttributes: [NSAttributedString.Key: Any] = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        return [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
    }()

    static let sourceAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]

    static let failedAttributes: [NSAttributedString.Key: Any] = {
        var attributes = translationAttributes
        attributes[.foregroundColor] = NSColor.tertiaryLabelColor
        return attributes
    }()

    /// Distance from the text view's top to its text container.
    static var containerOriginY: CGFloat { BilingualScrollView.highlightInset.height }

    var onMouseDown: ((NSPoint) -> Void)?
    var placeholder: String?
    var highlightColor: NSColor = .clear
    var highlightRange: NSRange? {
        didSet {
            if highlightRange != oldValue { needsDisplay = true }
        }
    }

    /// TextKit 1 is required for `NSLayoutManagerDelegate` paragraph spacing.
    static func make(editable: Bool) -> SegmentTextView {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)

        let view = SegmentTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 22), textContainer: container)
        view.textContainerInset = BilingualScrollView.highlightInset
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.drawsBackground = false
        view.isRichText = false
        view.importsGraphics = false
        view.usesFindBar = false
        view.font = font
        view.textColor = .labelColor
        view.isEditable = editable
        view.isSelectable = true
        view.allowsUndo = editable

        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.smartInsertDeleteEnabled = false

        if editable {
            view.typingAttributes = sourceAttributes
        } else {
            view.defaultParagraphStyle = translationAttributes[.paragraphStyle] as? NSParagraphStyle
        }
        return view
    }

    /// Height of the laid-out text, including the empty line after a trailing newline.
    var contentHeight: CGFloat {
        guard let manager = layoutManager, let container = textContainer else { return 0 }
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        let extra = manager.extraLineFragmentRect
        return max(used.maxY, extra.isEmpty ? 0 : extra.maxY, Self.font.ascender - Self.font.descender)
    }

    override func mouseDown(with event: NSEvent) {
        // Report the click before AppKit's tracking loop starts; selection and
        // editing continue as usual.
        onMouseDown?(convert(event.locationInWindow, from: nil))
        super.mouseDown(with: event)
    }

    /// Replaces the whole text as one undoable edit, so the undo stack never
    /// points at ranges of text that no longer exists.
    func replaceAllText(with text: String) {
        let range = NSRange(location: 0, length: (string as NSString).length)
        guard shouldChangeText(in: range, replacementString: text) else {
            string = text
            return
        }
        // Explicit attributes: a plain replacement would inherit a fallback
        // font (e.g. PingFang) from the text being replaced.
        textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: Self.sourceAttributes))
        didChangeText()
        setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    }

    override func draw(_ dirtyRect: NSRect) {
        // Drawn under the text; a background highlight is not limited to line rectangles.
        if let range = highlightRange, let bounds = highlightBounds(for: range) {
            highlightColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
        guard string.isEmpty, let placeholder else { return }
        let origin = textContainerOrigin
        (placeholder as NSString).draw(
            at: NSPoint(x: origin.x, y: origin.y),
            withAttributes: [.font: Self.font, .foregroundColor: NSColor.tertiaryLabelColor]
        )
    }

    /// Top of the text (excluding added spacing) on the line containing a character, in view coordinates.
    func lineTop(at characterIndex: Int) -> CGFloat? {
        guard let manager = layoutManager, characterIndex < (string as NSString).length else { return nil }
        let glyph = manager.glyphIndexForCharacter(at: characterIndex)
        return manager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil).minY + textContainerOrigin.y
    }

    /// The full column width, from the top of the segment's first line to the
    /// bottom of its last line, grown by the highlight inset.
    private func highlightBounds(for range: NSRange) -> NSRect? {
        guard let manager = layoutManager else { return nil }
        let glyphCount = manager.numberOfGlyphs
        let glyphRange = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)

        var top = CGFloat.greatestFiniteMagnitude
        var bottom = -CGFloat.greatestFiniteMagnitude
        if glyphRange.length > 0 {
            manager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
                top = min(top, usedRect.minY)
                bottom = max(bottom, usedRect.maxY)
            }
        } else if glyphRange.location < glyphCount {
            let used = manager.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            top = used.minY
            bottom = used.maxY
        } else if !manager.extraLineFragmentUsedRect.isEmpty {
            top = manager.extraLineFragmentUsedRect.minY
            bottom = manager.extraLineFragmentUsedRect.maxY
        }
        guard top <= bottom else { return nil }

        let origin = textContainerOrigin
        let inset = BilingualScrollView.highlightInset
        return NSRect(
            x: 0,
            y: origin.y + top - inset.height,
            width: bounds.width,
            height: bottom - top + inset.height * 2
        )
    }
}

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
