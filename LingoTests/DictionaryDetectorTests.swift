import XCTest
@testable import Lingo_Translate

final class DictionaryDetectorTests: XCTestCase {
    func testAcceptsWordsAndShortPhrases() {
        for text in [
            "ephemeral", "run", "don't", "well-known", "COVID-19", "naïve",
            "look forward to", "as well as", "日本語", "四面楚歌", "一举两得",
        ] {
            XCTAssertTrue(DictionaryDetector.isTerm(text), text)
        }
    }

    func testIgnoresQuotesAndSentencePunctuationAroundTheTerm() {
        XCTAssertTrue(DictionaryDetector.isTerm("  “ephemeral”, "))
        XCTAssertTrue(DictionaryDetector.isTerm("run."))
        XCTAssertTrue(DictionaryDetector.isTerm("\"look forward to?\""))
    }

    func testRejectsSentencesAndPunctuationInsideTheText() {
        for text in [
            "Hello, world.", "I love you, truly.", "really? yes",
            "这是一个句子，还有第二个。", "第一，第二",
        ] {
            XCTAssertFalse(DictionaryDetector.isTerm(text), text)
        }
    }

    func testRejectsCodeAddressesAndNumbers() {
        for text in [
            "https://example.com", "user@example.com", "let x = 1",
            "```swift", "array[0]", "42", "3.14", "1,000", "",
            "   ",
        ] {
            XCTAssertFalse(DictionaryDetector.isTerm(text), text)
        }
    }

    func testRejectsMultilineText() {
        XCTAssertFalse(DictionaryDetector.isTerm("first line\nsecond line"))
        XCTAssertFalse(DictionaryDetector.isTerm("first line\rsecond line"))
    }

    func testRejectsLongText() {
        XCTAssertFalse(DictionaryDetector.isTerm("今天天气真好我们出去走走吧"))
        XCTAssertFalse(DictionaryDetector.isTerm("This is a noticeably longer sentence with many words."))
        XCTAssertFalse(DictionaryDetector.isTerm(String(repeating: "a", count: 65)))
    }
}
