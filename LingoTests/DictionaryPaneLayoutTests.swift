import XCTest
@testable import Lingo_Translate

final class DictionaryPaneLayoutTests: XCTestCase {
    func testProposedHeightIsKeptWhenItFits() {
        XCTAssertEqual(DictionaryPaneLayout.height(180, available: 600), 180)
    }

    func testPaneNeverShrinksBelowItsMinimum() {
        XCTAssertEqual(DictionaryPaneLayout.height(0, available: 600), DictionaryPaneLayout.minimumHeight)
        XCTAssertEqual(DictionaryPaneLayout.height(-40, available: 600), DictionaryPaneLayout.minimumHeight)
    }

    func testPaneLeavesOneVisibleTextLineUnderTheHeader() {
        let available: CGFloat = 400
        let height = DictionaryPaneLayout.height(10_000, available: available)
        let columns = available - DictionaryPaneLayout.dividerHeight - height

        XCTAssertEqual(columns, DictionaryPaneLayout.minimumColumnsHeight, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(columns, SegmentTextView.lineHeight)
    }

    func testSmallWindowStillGivesThePaneItsMinimum() {
        let height = DictionaryPaneLayout.height(400, available: 120)
        XCTAssertEqual(height, DictionaryPaneLayout.minimumHeight)
        XCTAssertEqual(DictionaryPaneLayout.limits(available: 120).lowerBound, DictionaryPaneLayout.minimumHeight)
    }

    func testDefaultHeightIsUsable() {
        XCTAssertGreaterThan(AppSettings.defaultDictionaryHeight, DictionaryPaneLayout.minimumHeight)
    }

    func testDraggingUpGrowsThePane() {
        let start: CGFloat = 160
        let available: CGFloat = 600
        XCTAssertEqual(DictionaryPaneLayout.draggedHeight(start: start, translation: -40, available: available), 200)
        XCTAssertEqual(DictionaryPaneLayout.draggedHeight(start: start, translation: 40, available: available), 120)
    }

    func testDragKeepsItsBounds() {
        let available: CGFloat = 400
        let maximum = DictionaryPaneLayout.limits(available: available).upperBound
        XCTAssertEqual(
            DictionaryPaneLayout.draggedHeight(start: 150, translation: -10_000, available: available),
            maximum
        )
        XCTAssertEqual(
            DictionaryPaneLayout.draggedHeight(start: 150, translation: 10_000, available: available),
            DictionaryPaneLayout.minimumHeight
        )
    }
}
