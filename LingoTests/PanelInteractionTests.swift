import AppKit
import Carbon.HIToolbox
import SwiftUI
import XCTest
@testable import Lingo_Translate

@MainActor
final class PanelKeyActionTests: XCTestCase {
    private func keyEvent(_ keyCode: Int, modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(keyCode)
        ))
    }

    func testCommandWHidesThePanelInsteadOfClosingTheWindow() throws {
        XCTAssertEqual(PanelController.keyAction(for: try keyEvent(kVK_ANSI_W, modifiers: .command)), .hide)
    }

    func testCommandQHidesThePanelInsteadOfQuitting() throws {
        XCTAssertEqual(PanelController.keyAction(for: try keyEvent(kVK_ANSI_Q, modifiers: .command)), .hide)
    }

    func testPlainWAndQStayInTheText() throws {
        XCTAssertEqual(PanelController.keyAction(for: try keyEvent(kVK_ANSI_W, modifiers: [])), .none)
        XCTAssertEqual(PanelController.keyAction(for: try keyEvent(kVK_ANSI_Q, modifiers: [])), .none)
        XCTAssertEqual(PanelController.keyAction(for: try keyEvent(kVK_ANSI_W, modifiers: [.command, .shift])), .none)
    }

    func testEscapeHidesAndCommandReturnTranslates() throws {
        XCTAssertEqual(PanelController.keyAction(for: try keyEvent(kVK_Escape, modifiers: [])), .hide)
        XCTAssertEqual(PanelController.keyAction(for: try keyEvent(kVK_Return, modifiers: .command)), .translate)
        XCTAssertEqual(PanelController.keyAction(for: try keyEvent(kVK_Return, modifiers: [])), .none)
    }
}

final class PanelOutsideClickTests: XCTestCase {
    private let panelFrame = NSRect(x: 100, y: 200, width: 800, height: 480)

    func testClickOnThePanelIsNotAnOutsideClick() {
        let point = NSPoint(x: panelFrame.midX, y: panelFrame.midY)
        XCTAssertTrue(PanelController.isClickInsidePanel(
            windowNumber: 12,
            panelWindowNumber: 12,
            point: point,
            panelFrame: panelFrame
        ))
        // The click may reach the monitor without a window number.
        XCTAssertTrue(PanelController.isClickInsidePanel(
            windowNumber: 0,
            panelWindowNumber: 12,
            point: point,
            panelFrame: panelFrame
        ))
    }

    func testClickInAnotherApplicationIsAnOutsideClick() {
        XCTAssertFalse(PanelController.isClickInsidePanel(
            windowNumber: 7,
            panelWindowNumber: 12,
            point: NSPoint(x: panelFrame.midX, y: panelFrame.midY),
            panelFrame: panelFrame
        ))
        XCTAssertFalse(PanelController.isClickInsidePanel(
            windowNumber: 7,
            panelWindowNumber: 12,
            point: NSPoint(x: 20, y: 20),
            panelFrame: panelFrame
        ))
    }
}

@MainActor
final class TranslatorViewLayoutTests: XCTestCase {
    private func hostView() -> (NSView, NSWindow) {
        let model = TranslatorModel(settings: AppSettings())
        let hosting = NSHostingView(rootView: TranslatorView(model: model, openSettings: {}))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 480),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
        window.contentView = hosting
        hosting.frame = window.contentView!.bounds
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    private func firstDragView(in view: NSView) -> WindowDragView? {
        if let drag = view as? WindowDragView { return drag }
        for subview in view.subviews {
            if let found = firstDragView(in: subview) { return found }
        }
        return nil
    }

    /// `hitTest` takes a point in the receiver's superview coordinates.
    private func hitTest(_ point: NSPoint, inView view: NSView, of hosting: NSView) -> NSView? {
        guard let superview = hosting.superview else { return nil }
        return hosting.hitTest(view.convert(point, to: superview))
    }

    func testHeaderHasADragAreaCoveringTheEmptyTitleSpace() throws {
        let (hosting, _) = hostView()
        let dragView = try XCTUnwrap(firstDragView(in: hosting))

        XCTAssertTrue(dragView.mouseDownCanMoveWindow)
        let frame = dragView.convert(dragView.bounds, to: hosting)
        XCTAssertGreaterThan(frame.width, 100)
        XCTAssertGreaterThan(frame.height, 10)

        // Clicks on that empty header space reach the drag view, so the panel moves.
        let hit = hitTest(NSPoint(x: dragView.bounds.midX, y: dragView.bounds.midY), inView: dragView, of: hosting)
        XCTAssertNotNil(hit)
        XCTAssertTrue(hit === dragView || hit?.isDescendant(of: dragView) == true)
    }

    func testHeaderButtonsStayClickableAboveTheDragArea() throws {
        let (hosting, _) = hostView()
        let dragView = try XCTUnwrap(firstDragView(in: hosting))

        let trailing = NSPoint(x: dragView.bounds.maxX - 14, y: dragView.bounds.midY)
        let hit = hitTest(trailing, inView: dragView, of: hosting)
        XCTAssertNotNil(hit)
        XCTAssertFalse(hit === dragView)
    }
}
