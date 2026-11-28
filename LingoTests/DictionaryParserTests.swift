import XCTest
@testable import Lingo_Translate

final class DictionaryParserTests: XCTestCase {
    private let reply = """
    {
      "valid": true,
      "term": "ephemeral",
      "pronunciation": "/ɪˈfem(ə)rəl/",
      "senses": [
        {
          "partOfSpeech": "adj.",
          "definition": "短暂的；转瞬即逝的",
          "examples": [{"source": "Fame is often ephemeral.", "translation": "名声常常转瞬即逝。"}]
        }
      ]
    }
    """

    func testParsesAPlainJSONObject() {
        let entry = DictionaryParser.parse(reply)
        XCTAssertEqual(entry?.term, "ephemeral")
        XCTAssertEqual(entry?.pronunciation, "/ɪˈfem(ə)rəl/")
        XCTAssertEqual(entry?.senses.count, 1)
        XCTAssertEqual(entry?.senses.first?.partOfSpeech, "adj.")
        XCTAssertEqual(entry?.senses.first?.definition, "短暂的；转瞬即逝的")
        XCTAssertEqual(entry?.senses.first?.examples.first?.source, "Fame is often ephemeral.")
        XCTAssertEqual(entry?.senses.first?.examples.first?.translation, "名声常常转瞬即逝。")
    }

    func testFindsTheObjectInAFenceAndProse() {
        let wrapped = """
        Here is the entry:
        ```json
        \(reply)
        ```
        """
        XCTAssertEqual(DictionaryParser.parse(wrapped)?.term, "ephemeral")
    }

    func testInvalidFlagHidesTheEntry() {
        XCTAssertNil(DictionaryParser.parse("{\"valid\": false}"))
        XCTAssertNil(DictionaryParser.parse("{\"valid\": \"false\"}"))
        XCTAssertNil(DictionaryParser.parse("I cannot define this."))
        XCTAssertNil(DictionaryParser.parse("{\"valid\": true}"))
        XCTAssertNil(DictionaryParser.parse("{\"valid\": true, \"senses\": []}"))
    }

    func testDropsIncompleteSensesAndExamples() {
        let json = """
        {"valid": true, "term": "run", "senses": [
          {"definition": ""},
          {"partOfSpeech": "v.", "definition": "跑", "examples": [
            {"translation": "只有译文"},
            {"source": "I run.", "translation": "我跑步。"}
          ]}
        ]}
        """
        let entry = DictionaryParser.parse(json)
        XCTAssertEqual(entry?.senses.count, 1)
        XCTAssertEqual(entry?.senses.first?.examples.map(\.source), ["I run."])
        XCTAssertNil(entry?.pronunciation)
    }

    func testCapsSensesExamplesAndFieldLength() {
        let examples = (0..<5).map { "{\"source\": \"Example \($0)\", \"translation\": \"例 \($0)\"}" }
            .joined(separator: ",")
        let senses = (0..<7).map {
            "{\"partOfSpeech\": \"n.\", \"definition\": \"definition \($0)\", \"examples\": [\(examples)]}"
        }
        .joined(separator: ",")
        let longTerm = String(repeating: "a", count: 120)
        let entry = DictionaryParser.parse("{\"valid\": true, \"term\": \"\(longTerm)\", \"senses\": [\(senses)]}")

        XCTAssertEqual(entry?.term.count, 80)
        XCTAssertEqual(entry?.senses.count, DictionaryParser.maximumSenses)
        XCTAssertTrue(entry?.senses.allSatisfy { $0.examples.count == DictionaryParser.maximumExamples } == true)
    }

    func testMatchesKeysCaseInsensitively() {
        let json = """
        {"Valid": true, "Term": "run", "Senses": [{"PartOfSpeech": "v.", "Definition": "跑", "Examples": []}]}
        """
        XCTAssertEqual(DictionaryParser.parse(json)?.senses.first?.partOfSpeech, "v.")
    }
}
