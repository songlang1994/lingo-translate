import Foundation

struct LayoutSegment: Equatable {
    enum Kind: Equatable { case text, verbatim }

    /// 0-based closed range of lines.
    var lines: ClosedRange<Int>
    var kind: Kind
    /// Joined single-line text for `.text`; the original lines for `.verbatim`.
    var text: String
}

/// Deterministic, rule-based paragraph detection (no model involved). Used by
/// the fallback protocol and to rebuild segments when swapping languages.
enum LayoutSegmenter {
    private static let minimumWrap = 40
    private static let terminal: Set<Character> = Set(".!?;:。！？；：…")
    private static let closers: Set<Character> = Set("\"'”’」』）)]】》")
    private static let softEnds: Set<Character> = Set(",，、-‐–—/([{（【《“‘")
    private static let closingStarts: Set<Character> = Set(",.;:)]}，。、；：）")

    private static let listPattern = try! NSRegularExpression(
        pattern: #"^([-*+•·▪◦‣]|\d{1,3}[.)、]|[a-zA-Z][.)]|[（(]\d{1,3}[)）]|[一二三四五六七八九十]+、)\s+"#
    )
    private static let fencePattern = try! NSRegularExpression(pattern: #"^(```|~~~)"#)
    private static let rulePattern = try! NSRegularExpression(pattern: #"^([-=*_])\1{2,}$"#)
    private static let markdownHeadingPattern = try! NSRegularExpression(pattern: #"^#{1,6}\s"#)

    static func segments(of lines: [String]) -> [LayoutSegment] {
        let features = lines.enumerated().map { LineFeatures(index: $0.offset, raw: $0.element) }
        var result: [LayoutSegment] = []
        var i = 0
        let n = features.count

        while i < n {
            if features[i].isBlank {
                i += 1
                continue
            }

            if isFence(features[i].text) {
                var j = i + 1
                while j < n, !isFence(features[j].text) { j += 1 }
                j = min(j, n - 1)
                result.append(verbatim(lines, i...j))
                i = j + 1
                continue
            }

            var j = i
            while j + 1 < n, !features[j + 1].isBlank, !isFence(features[j + 1].text) { j += 1 }

            let block = Array(features[i...j])
            let wrap = block.map(\.width).max() ?? 0
            var current = [block[0]]

            func flush() {
                let range = current[0].index...current[current.count - 1].index
                if current.allSatisfy(\.hasNoLetters) {
                    result.append(verbatim(lines, range))
                } else {
                    result.append(LayoutSegment(lines: range, kind: .text, text: joined(current.map(\.text))))
                }
            }

            for (previous, next) in zip(block, block.dropFirst()) {
                let mustSplit = isStructuralBreak(previous, next, segmentFirst: current[0])
                if !mustSplit, isContinuation(previous, next, wrap: wrap) {
                    current.append(next)
                } else {
                    flush()
                    current = [next]
                }
            }
            flush()
            i = j + 1
        }
        return result
    }

    /// Text for a range of lines: rule segments are joined into prose and kept
    /// on separate lines, with a blank line where the original had one.
    static func joinedText(of lines: [String], in range: ClosedRange<Int>) -> String {
        let lower = max(range.lowerBound, 0)
        let upper = min(range.upperBound, lines.count - 1)
        guard lower <= upper else { return "" }

        let slice = Array(lines[lower...upper])
        var text = ""
        var previousEnd: Int?
        for segment in segments(of: slice) {
            if let previousEnd {
                text += segment.lines.lowerBound > previousEnd + 1 ? "\n\n" : "\n"
            }
            text += segment.text
            previousEnd = segment.lines.upperBound
        }
        return text
    }

    /// Joins trimmed lines: directly at wide characters or after a hyphenated
    /// word, otherwise with one space.
    static func joined(_ texts: [String]) -> String {
        guard var result = texts.first else { return "" }
        for next in texts.dropFirst() {
            result = join(result, next)
        }
        return result
    }

    // MARK: - Helpers

    private static func verbatim(_ lines: [String], _ range: ClosedRange<Int>) -> LayoutSegment {
        LayoutSegment(lines: range, kind: .verbatim, text: lines[range].joined(separator: "\n"))
    }

    private static func join(_ a: String, _ b: String) -> String {
        if let last = a.last, let first = b.first, isWide(last) || isWide(first) {
            return a + b
        }
        if let last = a.last, last == "-" || last == "‐" {
            let beforeLast = a.dropLast().last
            if beforeLast?.isLetter == true {
                return a + b
            }
        }
        return a + " " + b
    }

    private static func isStructuralBreak(_ previous: LineFeatures, _ next: LineFeatures, segmentFirst: LineFeatures) -> Bool {
        if next.isList || next.isHeading || next.isTable || next.isRule { return true }
        if previous.isHeading || previous.isTable || previous.isRule { return true }
        if next.indent != previous.indent {
            if previous.isList, next.indent == previous.contentColumn { return false }
            if previous.index == segmentFirst.index, next.indent < previous.indent { return false }
            return true
        }
        return false
    }

    private static func isContinuation(_ previous: LineFeatures, _ next: LineFeatures, wrap: Int) -> Bool {
        if let end = lastMeaningful(previous.text), softEnds.contains(end) { return true }
        if wrap < minimumWrap { return false }
        guard let first = next.text.first else { return false }
        if first.isASCII, first.isLowercase { return true }
        if closingStarts.contains(first) { return true }
        let spacing = isWide(first) ? 0 : 1
        return previous.width + spacing + displayWidth(firstWord(next.text)) > wrap
    }

    private static func lastMeaningful(_ text: String) -> Character? {
        var trimmed = Substring(text)
        while let last = trimmed.last, last.isWhitespace { trimmed = trimmed.dropLast() }
        while let last = trimmed.last, closers.contains(last) {
            trimmed = trimmed.dropLast()
        }
        return trimmed.last
    }

    private static func firstWord(_ text: String) -> String {
        guard let first = text.first else { return "" }
        if isWide(first) { return String(first) }
        return text.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
    }

    private static func isFence(_ text: String) -> Bool { matches(fencePattern, text) }

    fileprivate static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    fileprivate static func listPrefixWidth(_ text: String) -> Int? {
        let string = text as NSString
        guard let match = listPattern.firstMatch(in: text, range: NSRange(location: 0, length: string.length)) else {
            return nil
        }
        return displayWidth(string.substring(with: match.range))
    }

    fileprivate static func isHeading(_ text: String) -> Bool {
        if matches(markdownHeadingPattern, text) { return true }
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty, letters.contains(where: \.isASCII) else { return false }
        guard letters.filter(\.isASCII).allSatisfy(\.isUppercase) else { return false }
        guard displayWidth(text) <= 40, let last = text.last else { return false }
        return !terminal.contains(last)
    }

    fileprivate static func isRule(_ text: String) -> Bool { matches(rulePattern, text) }

    /// Display columns: tabs advance to the next multiple of 8, East Asian
    /// wide and fullwidth characters take two columns.
    static func displayWidth(_ text: String) -> Int {
        var width = 0
        for character in text {
            if character == "\t" {
                width += 8 - width % 8
            } else {
                width += isWide(character) ? 2 : 1
            }
        }
        return width
    }

    static func isWide(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x1100...0x115F, 0x231A...0x231B, 0x2329...0x232A, 0x23E9...0x23EC, 0x23F0, 0x23F3,
             0x25FD...0x25FE, 0x2614...0x2615, 0x2648...0x2653, 0x267F, 0x2693, 0x26A1,
             0x26AA...0x26AB, 0x26BD...0x26BE, 0x26C4...0x26C5, 0x26CE, 0x26D4, 0x26EA,
             0x26F2...0x26F3, 0x26F5, 0x26FA, 0x26FD, 0x2705, 0x270A...0x270B, 0x2728, 0x274C,
             0x274E, 0x2753...0x2755, 0x2757, 0x2795...0x2797, 0x27B0, 0x27BF, 0x2B1B...0x2B1C,
             0x2B50, 0x2B55, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xA000...0xA4CF, 0xA960...0xA97F, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE10...0xFE19,
             0xFE30...0xFE6F, 0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x16FE0...0x18CFF, 0x1B000...0x1B2FF,
             0x1F004, 0x1F0CF, 0x1F18E, 0x1F191...0x1F19A, 0x1F200...0x1F251, 0x1F300...0x1F64F,
             0x1F680...0x1F6FF, 0x1F7E0...0x1F7EB, 0x1F90C...0x1F9FF, 0x1FA70...0x1FAFF,
             0x20000...0x2FFFD, 0x30000...0x3FFFD:
            return true
        default:
            return false
        }
    }
}

private struct LineFeatures {
    let index: Int
    let text: String
    let isBlank: Bool
    let indent: Int
    let width: Int
    let isList: Bool
    let contentColumn: Int
    let isHeading: Bool
    let isTable: Bool
    let isRule: Bool
    let hasNoLetters: Bool

    init(index: Int, raw: String) {
        self.index = index
        let body = raw.drop { $0 == " " || $0 == "\t" }
        let leading = String(raw.prefix(raw.count - body.count))
        var trimmed = Substring(body)
        while let last = trimmed.last, last.isWhitespace { trimmed = trimmed.dropLast() }
        text = String(trimmed)

        isBlank = text.isEmpty
        indent = LayoutSegmenter.displayWidth(leading)
        width = indent + LayoutSegmenter.displayWidth(text)

        let listWidth = LayoutSegmenter.listPrefixWidth(text)
        isList = listWidth != nil
        contentColumn = indent + (listWidth ?? 0)

        isHeading = LayoutSegmenter.isHeading(text)
        isTable = text.filter { $0 == "|" }.count >= 2 || text.filter { $0 == "\t" }.count >= 2
        isRule = LayoutSegmenter.isRule(text)
        hasNoLetters = !text.contains(where: \.isLetter)
    }
}
