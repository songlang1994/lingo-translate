import AppKit
import XCTest
@testable import Lingo_Translate

@MainActor
final class SelectedTextReaderTests: XCTestCase {
    func testSubstringUsesTheAccessibilityRange() {
        let value = "Hello world"
        XCTAssertEqual(SelectedTextReader.substring(of: value, inRange: CFRange(location: 6, length: 5)), "world")
    }

    func testSubstringRejectsEmptyOrOutOfBoundsRanges() {
        let value = "Hi"
        XCTAssertNil(SelectedTextReader.substring(of: value, inRange: CFRange(location: 0, length: 0)))
        XCTAssertNil(SelectedTextReader.substring(of: value, inRange: CFRange(location: 1, length: 5)))
        XCTAssertNil(SelectedTextReader.substring(of: value, inRange: CFRange(location: -1, length: 1)))
    }

    func testPasteboardRestoreKeepsEveryTypeAndItem() throws {
        let name = NSPasteboard.Name("LingoTests.\(UUID().uuidString)")
        let pasteboard = NSPasteboard(name: name)
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        let first = NSPasteboardItem()
        first.setString("plain", forType: .string)
        first.setData(Data([0x01, 0x02]), forType: .tiff)
        let second = NSPasteboardItem()
        second.setString("https://example.com", forType: .URL)
        XCTAssertTrue(pasteboard.writeObjects([first, second]))

        let snapshot = SelectedTextReader.snapshot(of: pasteboard)
        XCTAssertEqual(snapshot.count, 2)

        pasteboard.clearContents()
        pasteboard.setString("copy result", forType: .string)
        SelectedTextReader.restore(snapshot, to: pasteboard)

        let restored = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored[0].string(forType: .string), "plain")
        XCTAssertEqual(restored[0].data(forType: .tiff), Data([0x01, 0x02]))
        XCTAssertEqual(restored[1].string(forType: .URL), "https://example.com")
    }

    func testRestoringAnEmptyPasteboardLeavesItEmpty() {
        let name = NSPasteboard.Name("LingoTests.\(UUID().uuidString)")
        let pasteboard = NSPasteboard(name: name)
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        pasteboard.setString("copy result", forType: .string)
        SelectedTextReader.restore([], to: pasteboard)

        XCTAssertNil(pasteboard.string(forType: .string))
    }
}
