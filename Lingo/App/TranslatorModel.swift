import AppKit
import Combine

struct TranslationSegment: Equatable {
    enum State: Equatable { case streaming, done, failed }

    /// 0-based closed range of lines in `TranslatorModel.requestLines`.
    var lines: ClosedRange<Int>
    var text: String
    var state: State
}

@MainActor
final class TranslatorModel: ObservableObject {
    /// Source text exactly as the user typed it. The model never rewrites it.
    @Published private(set) var input = ""
    @Published private(set) var segments: [TranslationSegment] = [] {
        didSet { remapHighlight(from: oldValue) }
    }
    @Published var isTranslating = false
    @Published var errorMessage: String?
    @Published var copied = false
    @Published var focusToken = 0
    @Published private(set) var highlightedSegment: Int?
    /// Dictionary entry for a word or short phrase, shown under both columns.
    @Published private(set) var dictionaryState: DictionaryState = .none

    /// Snapshot of the source lines the current `segments` refer to.
    private(set) var requestLines: [String] = []

    private(set) var sourceCode: String
    private(set) var targetCode: String

    private let settings: AppSettings
    private let client: TranslationClient
    private let dictionaryClient: DictionaryClient?
    private var translationTask: Task<Void, Never>?
    private var dictionaryTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var copyTask: Task<Void, Never>?
    private var requestID = 0
    private var hasPendingTranslation = false

    /// Replies longer than this without any opening tag switch to the fallback protocol.
    static let maximumUntaggedReply = 300

    init(
        settings: AppSettings,
        client: TranslationClient? = nil,
        dictionaryClient: DictionaryClient? = nil
    ) {
        self.settings = settings
        self.client = client ?? ResponsesClient()
        if let dictionaryClient {
            self.dictionaryClient = dictionaryClient
        } else {
            // An injected translation client comes from tests; letting the
            // default dictionary client run there would reach the network.
            self.dictionaryClient = client == nil ? ResponsesDictionaryClient() : nil
        }
        sourceCode = settings.sourceCode
        targetCode = settings.targetCode
    }

    var sourceLanguage: Language { Language.named(sourceCode) }
    var targetLanguage: Language { Language.named(targetCode) }

    /// A detected source has no fixed language, so there is nothing to swap.
    var canSwapLanguages: Bool {
        !sourceLanguage.isAutomatic && !targetLanguage.isAutomatic
    }

    var output: String {
        Self.joinedOutput(segments, lines: requestLines).text
    }

    var canCopy: Bool {
        !output.isEmpty && errorMessage == nil && !isTranslating && isOutputCurrent
    }

    /// The segments describe the text currently in the editor and no newer
    /// translation is waiting to start. A column with no translation at all is
    /// not current, so an empty panel offers nothing to clear.
    var isOutputCurrent: Bool {
        !hasPendingTranslation && !requestLines.isEmpty && TextLines.split(input) == requestLines
    }

    var isSourceEmpty: Bool {
        trimmedInput.isEmpty
    }

    /// The card belongs to the current output: it hides while the source is
    /// edited and while a newer translation is waiting to start.
    var isDictionaryVisible: Bool {
        guard isOutputCurrent else { return false }
        if case .none = dictionaryState { return false }
        return true
    }

    /// Height of the dictionary pane, shared with the settings so the user's
    /// drag survives a relaunch. The view clamps it to the current window.
    var dictionaryPaneHeight: CGFloat {
        get { settings.dictionaryHeight }
        set { settings.dictionaryHeight = newValue }
    }

    func requestFocus() {
        focusToken &+= 1
    }

    func prefill(_ text: String) {
        // Reopening the panel on the same selection must not reset the output.
        guard text != input else { return }
        input = text
        validateHighlight()
        if trimmedInput.isEmpty {
            scheduleTranslation()
        } else {
            translateNow()
        }
    }

    /// Called by the editor after the user changes the source text. Editing
    /// never starts a translation: a queued one is dropped, a running request
    /// keeps streaming against the text it started with, and the result is
    /// marked stale until the user asks for a new translation.
    func updateInput(_ text: String) {
        guard text != input else { return }
        debounceTask?.cancel()
        debounceTask = nil
        hasPendingTranslation = false
        errorMessage = nil
        input = text
        cancelDictionary(clearing: true)
        validateHighlight()
    }

    /// Clears both columns and puts the caret back in the empty source.
    func clear() {
        debounceTask?.cancel()
        debounceTask = nil
        hasPendingTranslation = false
        cancelRequest()
        cancelDictionary(clearing: true)
        errorMessage = nil
        input = ""
        requestLines = []
        segments = []
        highlightedSegment = nil
        requestFocus()
    }

    // MARK: - Highlight

    /// Toggles the highlight of both columns for one segment, so clicking the
    /// highlighted segment again clears it. Blank segments cannot be highlighted,
    /// and neither can output that no longer matches the source text.
    func highlightSegment(at index: Int?) {
        guard isOutputCurrent, let index, !isBlankSegment(index) else {
            clearHighlight()
            return
        }
        highlightedSegment = index == highlightedSegment ? nil : index
    }

    func clearHighlight() {
        guard highlightedSegment != nil else { return }
        highlightedSegment = nil
    }

    /// Segments can be inserted before the highlighted one (retry, fallback,
    /// failed lines), so the highlight follows its lines rather than its index.
    private func remapHighlight(from oldSegments: [TranslationSegment]) {
        guard let index = highlightedSegment else { return }
        guard oldSegments.indices.contains(index) else {
            highlightedSegment = nil
            return
        }
        let first = oldSegments[index].lines.lowerBound
        highlightedSegment = segments.firstIndex { $0.lines.contains(first) }
    }

    private func validateHighlight() {
        guard let index = highlightedSegment else { return }
        if !isOutputCurrent || isBlankSegment(index) {
            highlightedSegment = nil
        }
    }

    private func isBlankSegment(_ index: Int) -> Bool {
        guard segments.indices.contains(index) else { return true }
        let segment = segments[index]
        let lines = TextLines.split(input)
        let sourceIsBlank = segment.lines.allSatisfy { !lines.indices.contains($0) || TextLines.isBlank(lines[$0]) }
        let translationIsBlank = segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return sourceIsBlank && translationIsBlank
    }

    // MARK: - Languages

    func selectSource(_ code: String) {
        guard code != sourceCode else { return }
        sourceCode = code
        settings.sourceCode = code
        scheduleTranslation()
    }

    func selectTarget(_ code: String) {
        guard code != targetCode, code != Language.automatic.code else { return }
        targetCode = code
        settings.targetCode = code
        scheduleTranslation()
    }

    func swapLanguages() {
        guard canSwapLanguages else { return }

        let previousSource = sourceLanguage
        let newSource = targetLanguage
        var newTarget = previousSource
        if newTarget == newSource {
            newTarget = newSource.code == "en" ? Language.named("zh-Hans") : Language.named("en")
        }

        let canSwapText = !isTranslating && !output.isEmpty && isOutputCurrent

        debounceTask?.cancel()
        hasPendingTranslation = false
        cancelRequest()
        cancelDictionary(clearing: true)
        errorMessage = nil

        sourceCode = newSource.code
        targetCode = newTarget.code
        settings.sourceCode = newSource.code
        settings.targetCode = newTarget.code

        if canSwapText {
            let swapped = Self.swapped(segments, lines: requestLines)
            input = swapped.input
            requestLines = TextLines.split(swapped.input)
            segments = swapped.segments
            highlightedSegment = nil
        } else {
            startTranslation()
        }
    }

    // MARK: - Translation

    func translateNow() {
        debounceTask?.cancel()
        hasPendingTranslation = false
        startTranslation()
    }

    func stopTranslation() {
        guard isTranslating else { return }
        debounceTask?.cancel()
        debounceTask = nil
        hasPendingTranslation = false
        cancelRequest()
        // A finished entry stays useful; an unfinished lookup has nothing to show.
        cancelDictionary(clearing: false)
    }

    func copyOutput() {
        guard canCopy else { return }
        let text = output

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        copied = true
        copyTask?.cancel()
        copyTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            self?.copied = false
        }
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Stops the running request but keeps the segments it already produced.
    private func cancelRequest() {
        translationTask?.cancel()
        translationTask = nil
        requestID += 1
        isTranslating = false
        for index in segments.indices where segments[index].state == .streaming {
            segments[index].state = .done
        }
    }

    private func scheduleTranslation() {
        debounceTask?.cancel()
        // The old entry and the pending translation both belong to the old
        // language pair.
        cancelDictionary(clearing: true)

        guard !trimmedInput.isEmpty else {
            hasPendingTranslation = false
            debounceTask = nil
            cancelRequest()
            errorMessage = nil
            requestLines = []
            segments = []
            highlightedSegment = nil
            return
        }

        hasPendingTranslation = true
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.startTranslation()
        }
    }

    private func startTranslation() {
        hasPendingTranslation = false
        guard !trimmedInput.isEmpty else { return }

        let source = sourceLanguage
        let target = targetLanguage
        guard !target.isAutomatic else { return }

        let configuration = settings.configuration
        let lines = TextLines.split(input)

        translationTask?.cancel()
        requestID += 1
        let currentRequestID = requestID

        errorMessage = nil
        isTranslating = true
        requestLines = lines
        segments = []
        highlightedSegment = nil

        startDictionaryLookup(
            term: trimmedInput,
            source: source,
            target: target,
            configuration: configuration,
            requestID: currentRequestID
        )

        translationTask = Task { [weak self] in
            await self?.translate(
                lines: lines,
                source: source,
                target: target,
                configuration: configuration,
                requestID: currentRequestID
            )
        }
    }

    /// Starts the dictionary request next to the translation. A missing entry,
    /// an invalid reply, or an error only hides the card.
    private func startDictionaryLookup(
        term: String,
        source: Language,
        target: Language,
        configuration: Configuration,
        requestID currentRequestID: Int
    ) {
        cancelDictionary(clearing: true)
        guard let dictionaryClient, DictionaryDetector.isTerm(term) else { return }
        dictionaryState = .loading

        dictionaryTask = Task { [weak self, dictionaryClient] in
            let entry: DictionaryEntry?
            do {
                entry = try await dictionaryClient.lookup(
                    term: term,
                    source: source,
                    target: target,
                    configuration: configuration
                )
            } catch {
                entry = nil
            }
            guard !Task.isCancelled, let self, self.requestID == currentRequestID else { return }
            self.dictionaryTask = nil
            self.dictionaryState = entry.map(DictionaryState.entry) ?? .none
        }
    }

    /// Cancels an in-flight lookup. `clearing` also drops a finished entry; a
    /// cancelled but unfinished lookup always clears the loading state.
    private func cancelDictionary(clearing: Bool) {
        dictionaryTask?.cancel()
        dictionaryTask = nil
        if clearing || dictionaryState == .loading {
            dictionaryState = .none
        }
    }

    private struct UntaggedReply: Error {}

    private func translate(
        lines: [String],
        source: Language,
        target: Language,
        configuration: Configuration,
        requestID currentRequestID: Int
    ) async {
        let isCurrent = { [weak self] in self?.requestID == currentRequestID && !Task.isCancelled }
        let instructions = Prompt.lineRangeInstructions(source: source, target: target)
        let allLines = IndexSet(integersIn: lines.indices)

        // Main request: numbered lines, the model picks paragraph boundaries.
        var untaggedReply: String?
        do {
            let reply = try await request(
                instructions: instructions,
                input: Prompt.numberedInput(lines: lines),
                configuration: configuration,
                requestID: currentRequestID
            ) { [weak self] text in
                let parsed = SegmentParser.parse(text, mode: .lineRanges(allowedLines: allLines), lines: lines, isFinal: false)
                guard parsed.foundAnyTag else {
                    return text.trimmingCharacters(in: .whitespacesAndNewlines).count <= Self.maximumUntaggedReply
                }
                self?.segments = Self.segments(from: parsed.segments)
                return true
            }
            guard isCurrent() else { return }

            let parsed = SegmentParser.parse(reply, mode: .lineRanges(allowedLines: allLines), lines: lines, isFinal: true)
            if parsed.foundAnyTag {
                segments = Self.segments(from: parsed.segments)
            } else {
                untaggedReply = reply
            }
        } catch is UntaggedReply {
            guard isCurrent() else { return }
            untaggedReply = ""
        } catch {
            guard isCurrent() else { return }
            finish(failingMissingLinesOf: lines, error: error, configuration: configuration)
            return
        }

        if let untaggedReply {
            await translateWithFallback(
                lines: lines,
                source: source,
                target: target,
                configuration: configuration,
                untaggedReply: untaggedReply,
                requestID: currentRequestID
            )
            return
        }

        // Retry once for non-blank lines the model skipped, keeping their numbers.
        let missing = SegmentParser.missingLines(in: segments.map(\.lines), lines: lines)
        if !missing.isEmpty {
            let base = segments
            do {
                let reply = try await request(
                    instructions: instructions,
                    input: Prompt.numberedInput(lines: lines, indices: missing),
                    configuration: configuration,
                    requestID: currentRequestID
                ) { [weak self] text in
                    let parsed = SegmentParser.parse(text, mode: .lineRanges(allowedLines: missing), lines: lines, isFinal: false)
                    self?.segments = Self.merged(base, Self.segments(from: parsed.segments))
                    return true
                }
                guard isCurrent() else { return }
                let parsed = SegmentParser.parse(reply, mode: .lineRanges(allowedLines: missing), lines: lines, isFinal: true)
                segments = Self.merged(base, Self.segments(from: parsed.segments))
            } catch {
                guard isCurrent() else { return }
                segments = base
            }
        }

        finish(failingMissingLinesOf: lines, error: nil, configuration: configuration)
    }

    /// The model ignored the line-range format: segment locally and send `<s id="N">` segments.
    private func translateWithFallback(
        lines: [String],
        source: Language,
        target: Language,
        configuration: Configuration,
        untaggedReply: String,
        requestID currentRequestID: Int
    ) async {
        let isCurrent = { [weak self] in self?.requestID == currentRequestID && !Task.isCancelled }
        let layout = LayoutSegmenter.segments(of: lines)
        let textSegments = layout.filter { $0.kind == .text }
        let verbatim = layout
            .filter { $0.kind == .verbatim }
            .map { TranslationSegment(lines: $0.lines, text: $0.text, state: .done) }
        let mode = SegmentParser.Mode.segmentIDs(ranges: textSegments.map(\.lines))

        segments = verbatim
        guard !textSegments.isEmpty else {
            finish(failingMissingLinesOf: lines, error: nil, configuration: configuration)
            return
        }

        do {
            let reply = try await request(
                instructions: Prompt.segmentIDInstructions(source: source, target: target),
                input: Prompt.segmentInput(textSegments.map(\.text)),
                configuration: configuration,
                requestID: currentRequestID
            ) { [weak self] text in
                let parsed = SegmentParser.parse(text, mode: mode, lines: lines, isFinal: false)
                self?.segments = Self.merged(verbatim, Self.segments(from: parsed.segments))
                return true
            }
            guard isCurrent() else { return }

            let parsed = SegmentParser.parse(reply, mode: mode, lines: lines, isFinal: true)
            if parsed.foundAnyTag {
                segments = Self.merged(verbatim, Self.segments(from: parsed.segments))
            } else {
                segments = Self.wholeReply(reply, lines: lines)
            }
            finish(failingMissingLinesOf: lines, error: nil, configuration: configuration)
        } catch {
            guard isCurrent() else { return }
            // Without alignment the complete first reply is still a usable translation.
            if !untaggedReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments = Self.wholeReply(untaggedReply, lines: lines)
                finish(failingMissingLinesOf: lines, error: nil, configuration: configuration)
            } else {
                finish(failingMissingLinesOf: lines, error: error, configuration: configuration)
            }
        }
    }

    /// Marks remaining untranslated lines as failed. An error is shown only when nothing was translated.
    private func finish(failingMissingLinesOf lines: [String], error: Error?, configuration: Configuration) {
        var finished = segments
        for index in finished.indices where finished[index].state == .streaming {
            finished[index].state = .done
        }

        let hasTranslation = finished.contains { $0.state == .done }
        if let error, !hasTranslation {
            segments = []
            errorMessage = Self.message(for: error, configuration: configuration)
        } else {
            segments = Self.addingFailedSegments(to: finished, lines: lines)
        }
        isTranslating = false
        translationTask = nil
    }

    /// Runs one request and reports the accumulated reply after every delta.
    /// `onText` returns false to abandon the request, which then throws `UntaggedReply`.
    private func request(
        instructions: String,
        input: String,
        configuration: Configuration,
        requestID currentRequestID: Int,
        onText: @escaping (String) -> Bool
    ) async throws -> String {
        var streamed = ""
        var abandoned = false
        var inner: Task<String, Error>?

        inner = Task { @MainActor [client] in
            try await client.complete(
                instructions: instructions,
                input: input,
                configuration: configuration
            ) { [weak self] delta in
                guard !abandoned, self?.requestID == currentRequestID else { return }
                streamed += delta
                if !onText(streamed) {
                    abandoned = true
                    inner?.cancel()
                }
            }
        }

        let task = inner!
        do {
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch {
            if abandoned { throw UntaggedReply() }
            throw error
        }
    }

    // MARK: - Pure helpers

    static func segments(from parsed: [ParsedSegment]) -> [TranslationSegment] {
        parsed.map { TranslationSegment(lines: $0.lines, text: $0.text, state: $0.isComplete ? .done : .streaming) }
    }

    /// Merges two sorted segment lists, trimming any overlap so ranges stay disjoint.
    static func merged(_ base: [TranslationSegment], _ extra: [TranslationSegment]) -> [TranslationSegment] {
        let sorted = (base + extra).enumerated().sorted {
            ($0.element.lines.lowerBound, $0.offset) < ($1.element.lines.lowerBound, $1.offset)
        }
        var result: [TranslationSegment] = []
        for (_, segment) in sorted {
            var segment = segment
            if let previous = result.last, segment.lines.lowerBound <= previous.lines.upperBound {
                let lower = previous.lines.upperBound + 1
                guard lower <= segment.lines.upperBound else {
                    if !segment.text.isEmpty {
                        result[result.count - 1].text += "\n" + segment.text
                    }
                    continue
                }
                segment.lines = lower...segment.lines.upperBound
            }
            result.append(segment)
        }
        return result
    }

    /// Adds one `.failed` segment per run of untranslated non-blank lines.
    /// Runs separated only by blank lines are combined.
    static func addingFailedSegments(to segments: [TranslationSegment], lines: [String]) -> [TranslationSegment] {
        let covered = segments.map(\.lines)
        let missing = SegmentParser.missingLines(in: covered, lines: lines)
        guard !missing.isEmpty else { return segments }

        var coveredLines = IndexSet()
        for range in covered { coveredLines.insert(integersIn: range) }

        var failed: [TranslationSegment] = []
        var runStart: Int?
        var runEnd = 0
        for index in missing {
            if let start = runStart {
                let gapIsBlank = (runEnd + 1..<index).allSatisfy {
                    TextLines.isBlank(lines[$0]) && !coveredLines.contains($0)
                }
                if gapIsBlank {
                    runEnd = index
                    continue
                }
                failed.append(TranslationSegment(lines: start...runEnd, text: "", state: .failed))
            }
            runStart = index
            runEnd = index
        }
        if let start = runStart {
            failed.append(TranslationSegment(lines: start...runEnd, text: "", state: .failed))
        }
        return merged(segments, failed)
    }

    static func wholeReply(_ reply: String, lines: [String]) -> [TranslationSegment] {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !lines.isEmpty else { return [] }
        return [TranslationSegment(lines: 0...(lines.count - 1), text: text, state: .done)]
    }

    /// Joins translated segments in order, skipping failed ones. Segments separated
    /// by a blank source line get a blank line between them. Also returns the
    /// lines each segment occupies in the joined text.
    static func joinedOutput(
        _ segments: [TranslationSegment],
        lines: [String]
    ) -> (text: String, ranges: [ClosedRange<Int>]) {
        var text = ""
        var ranges: [ClosedRange<Int>] = []
        var line = 0
        var previous: TranslationSegment?

        for segment in segments where segment.state != .failed {
            if let previous {
                let gap = (previous.lines.upperBound + 1)..<segment.lines.lowerBound
                let hasBlankLine = gap.contains { lines.indices.contains($0) && TextLines.isBlank(lines[$0]) }
                text += hasBlankLine ? "\n\n" : "\n"
                line += hasBlankLine ? 2 : 1
            }
            let count = TextLines.split(segment.text).count
            ranges.append(line...(line + count - 1))
            line += count - 1
            text += segment.text
            previous = segment
        }
        return (text, ranges)
    }

    /// Swapping languages with a finished translation needs no request: the
    /// translation becomes the source, and each segment's original lines become
    /// its translation.
    static func swapped(
        _ segments: [TranslationSegment],
        lines: [String]
    ) -> (input: String, segments: [TranslationSegment]) {
        let joined = joinedOutput(segments, lines: lines)
        let included = segments.filter { $0.state != .failed }
        let swapped = zip(included, joined.ranges).map { segment, range in
            TranslationSegment(
                lines: range,
                text: LayoutSegmenter.joinedText(of: lines, in: segment.lines),
                state: .done
            )
        }
        return (joined.text, swapped)
    }

    private static func message(for error: Error, configuration: Configuration) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "No network connection."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Cannot reach \(configuration.url?.host ?? "the server")."
            case .timedOut:
                return "The request timed out."
            case .cancelled:
                return ""
            case .appTransportSecurityRequiresSecureConnection:
                return "The endpoint must use HTTPS."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
