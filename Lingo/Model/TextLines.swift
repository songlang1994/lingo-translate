import Foundation

/// Splits text into lines the same way `NSTextView` splits paragraphs
/// (`\n`, `\r\n`, `\r`, `\u{2029}`, …), so a line index maps directly to a
/// character range in the text view.
enum TextLines {
    /// Character ranges of every line, excluding line terminators. Text that is
    /// empty or ends with a terminator gets an empty last line, matching the
    /// extra line fragment the text view lays out.
    static func ranges(in text: NSString) -> [NSRange] {
        var result: [NSRange] = []
        let length = text.length
        var location = 0

        while location < length {
            var start = 0
            var end = 0
            var contentsEnd = 0
            text.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            result.append(NSRange(location: start, length: contentsEnd - start))
            location = end
        }

        if let last = result.last, NSMaxRange(last) == length {
            return result
        }
        result.append(NSRange(location: length, length: 0))
        return result
    }

    static func split(_ text: String) -> [String] {
        let string = text as NSString
        return ranges(in: string).map { string.substring(with: $0) }
    }

    static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
