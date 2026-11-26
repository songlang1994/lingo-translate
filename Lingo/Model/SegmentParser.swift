import Foundation

struct ParsedSegment: Equatable {
    /// 0-based closed range of lines in the request snapshot.
    var lines: ClosedRange<Int>
    var text: String
    var isComplete: Bool
}

struct SegmentParseResult: Equatable {
    /// Sorted by line, non-overlapping.
    var segments: [ParsedSegment]
    var foundAnyTag: Bool
}

/// Parses `<s lines="A-B">…</s>` / `<s id="N">…</s>` replies. Stateless: call it
/// with the whole accumulated reply after every delta.
enum SegmentParser {
    enum Mode: Equatable {
        /// Main and retry requests. Ranges are shrunk to `allowedLines`.
        case lineRanges(allowedLines: IndexSet)
        /// Fallback protocol: id `N` (1-based) maps to `ranges[N - 1]`.
        case segmentIDs(ranges: [ClosedRange<Int>])
    }

    private static let closeTag = "</s>"

    private static let lineRangeTag = try! NSRegularExpression(
        pattern: #"(?:^|</s>)[ \t]*<s lines="\s*(\d+)\s*(?:[-–]\s*(\d+))?\s*">"#,
        options: [.anchorsMatchLines]
    )
    private static let idTag = try! NSRegularExpression(
        pattern: #"(?:^|</s>)[ \t]*<s id="\s*(\d+)\s*(?:[-–]\s*(\d+))?\s*">"#,
        options: [.anchorsMatchLines]
    )
    private static let partialOpenTag = try! NSRegularExpression(pattern: #"^<s (lines|id)="[^"]*"?$"#)

    static func parse(_ text: String, mode: Mode, lines: [String], isFinal: Bool) -> SegmentParseResult {
        let string = text as NSString
        let regex: NSRegularExpression
        switch mode {
        case .lineRanges: regex = lineRangeTag
        case .segmentIDs: regex = idTag
        }

        let matches = regex.matches(in: text, range: NSRange(location: 0, length: string.length))
        guard !matches.isEmpty else {
            return SegmentParseResult(segments: [], foundAnyTag: false)
        }

        var raw: [(first: Int, last: Int?, text: String, isComplete: Bool)] = []
        for (index, match) in matches.enumerated() {
            let start = NSMaxRange(match.range)
            let end = index + 1 < matches.count ? matches[index + 1].range.location : string.length
            var content = string.substring(with: NSRange(location: start, length: max(end - start, 0)))
            let isLast = index == matches.count - 1

            var isClosed = false
            if let close = content.range(of: closeTag, options: .backwards) {
                content = String(content[..<close.lowerBound])
                isClosed = true
            } else if isLast, !isFinal {
                content = withheldTail(of: content)
            }

            let first = Int(string.substring(with: match.range(at: 1))) ?? 0
            let lastRange = match.range(at: 2)
            let last = lastRange.location == NSNotFound ? nil : Int(string.substring(with: lastRange))

            raw.append((
                first,
                last,
                content.trimmingCharacters(in: .whitespacesAndNewlines),
                !isLast || isClosed || isFinal
            ))
        }

        var segments: [ParsedSegment] = []
        switch mode {
        case let .lineRanges(allowedLines):
            for item in raw {
                let range: ClosedRange<Int>
                switch validatedRange(first: item.first, last: item.last ?? item.first, lines: lines, allowed: allowedLines) {
                case .outOfBounds:
                    continue
                case .notAllowed:
                    appendToPrevious(item.text, in: &segments)
                    continue
                case let .valid(validRange):
                    range = validRange
                }
                var lower = range.lowerBound
                if let previous = segments.last, lower <= previous.lines.upperBound {
                    lower = previous.lines.upperBound + 1
                }
                guard lower <= range.upperBound else {
                    appendToPrevious(item.text, in: &segments)
                    continue
                }
                segments.append(ParsedSegment(lines: lower...range.upperBound, text: item.text, isComplete: item.isComplete))
            }

        case let .segmentIDs(ranges):
            var seen = Set<Int>()
            for item in raw {
                let id = item.first
                guard id >= 1, id <= ranges.count, seen.insert(id).inserted else { continue }
                let range = ranges[id - 1]
                guard range.lowerBound >= 0, range.upperBound < lines.count else { continue }
                segments.append(ParsedSegment(lines: range, text: item.text, isComplete: item.isComplete))
            }
            segments.sort { $0.lines.lowerBound < $1.lines.lowerBound }
        }

        return SegmentParseResult(segments: segments, foundAnyTag: true)
    }

    /// Non-blank lines in `scope` (all lines by default) not covered by any range.
    static func missingLines(in ranges: [ClosedRange<Int>], lines: [String], scope: IndexSet? = nil) -> IndexSet {
        var covered = IndexSet()
        for range in ranges {
            covered.insert(integersIn: range)
        }
        var missing = IndexSet()
        for index in scope ?? IndexSet(integersIn: lines.indices)
        where lines.indices.contains(index) && !covered.contains(index) && !TextLines.isBlank(lines[index]) {
            missing.insert(index)
        }
        return missing
    }

    // MARK: - Helpers

    private enum RangeValidation {
        case valid(ClosedRange<Int>)
        case outOfBounds
        case notAllowed
    }

    /// Converts a 1-based model range to a 0-based range within the request.
    private static func validatedRange(first: Int, last: Int, lines: [String], allowed: IndexSet) -> RangeValidation {
        var lower = first - 1
        var upper = max(last, first) - 1
        guard upper >= 0, lower < lines.count else { return .outOfBounds }
        lower = max(lower, 0)
        upper = min(upper, lines.count - 1)

        // Shrink to allowed lines: start at the first allowed line and stop
        // before any non-blank line outside this request.
        guard let start = allowed.integerGreaterThanOrEqualTo(lower), start <= upper else { return .notAllowed }
        var end = start
        var index = start + 1
        while index <= upper {
            if allowed.contains(index) {
                end = index
            } else if !TextLines.isBlank(lines[index]) {
                break
            }
            index += 1
        }
        return .valid(start...end)
    }

    private static func appendToPrevious(_ text: String, in segments: inout [ParsedSegment]) {
        guard !segments.isEmpty, !text.isEmpty else { return }
        let index = segments.count - 1
        segments[index].text += segments[index].text.isEmpty ? text : "\n" + text
    }

    /// Hides the unfinished tail of a streaming segment: a partial `</s>` at
    /// the end, or a last line that may become the next opening tag.
    private static func withheldTail(of content: String) -> String {
        var content = content

        let lastLineStart = content.range(of: "\n", options: .backwards)?.upperBound ?? content.startIndex
        let lastLine = content[lastLineStart...].drop { $0 == " " || $0 == "\t" }
        if lastLine.hasPrefix("<"), isPossibleOpenTag(String(lastLine)) {
            content = String(content[..<lastLineStart])
        }

        var trimmed = Substring(content)
        while let last = trimmed.last, last.isWhitespace { trimmed = trimmed.dropLast() }
        for prefix in ["</s", "</", "<"] where trimmed.hasSuffix(prefix) {
            return String(trimmed.dropLast(prefix.count))
        }
        return content
    }

    private static func isPossibleOpenTag(_ line: String) -> Bool {
        if "<s lines=\"".hasPrefix(line) || "<s id=\"".hasPrefix(line) { return true }
        let range = NSRange(location: 0, length: (line as NSString).length)
        return partialOpenTag.firstMatch(in: line, range: range) != nil
    }
}
