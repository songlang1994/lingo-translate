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

@MainActor
final class DictionaryPaneViewLayoutTests: XCTestCase {
    private let entry = DictionaryEntry(
        term: "ephemeral",
        pronunciation: "/ɪˈfem(ə)rəl/",
        senses: [
            .init(
                partOfSpeech: "adj.",
                definition: "短暂的；转瞬即逝的",
                examples: [.init(source: "Fame is often ephemeral.", translation: "名声常常转瞬即逝。")]
            )
        ]
    )

    /// Hosts a panel that shows the dictionary pane at the given stored height,
    /// waits for the entry, and returns the columns' laid-out height.
    private func columnsHeight(storedHeight: CGFloat, windowHeight: CGFloat) async throws -> CGFloat {
        let settings = AppSettings()
        let original = settings.dictionaryHeight
        defer { settings.dictionaryHeight = original }
        settings.dictionaryHeight = storedHeight

        let model = TranslatorModel(
            settings: settings,
            client: ScriptedClient([.reply("<s lines=\"1\">短暂的</s>")]),
            dictionaryClient: ScriptedDictionaryClient([entry])
        )
        model.prefill("ephemeral")
        let deadline = Date().addingTimeInterval(5)
        while (model.isTranslating || model.isDictionaryLookupPending), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(model.isDictionaryVisible)

        let hosting = NSHostingView(rootView: TranslatorView(model: model, openSettings: {}))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: windowHeight),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
        window.contentView = hosting
        hosting.frame = window.contentView!.bounds
        hosting.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 100_000_000)
        hosting.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(firstView(of: BilingualScrollView.self, in: hosting))
        return scrollView.frame.height
    }

    private func firstView<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let found = firstView(of: type, in: subview) { return found }
        }
        return nil
    }

    func testSmallWindowKeepsOneTextLineUnderTheHeader() async throws {
        let columns = try await columnsHeight(storedHeight: 400, windowHeight: 300)
        XCTAssertGreaterThanOrEqual(columns, DictionaryPaneLayout.minimumColumnsHeight - 1)
    }

    func testPaneFollowsTheStoredHeight() async throws {
        let small = try await columnsHeight(storedHeight: 120, windowHeight: 760)
        let large = try await columnsHeight(storedHeight: 220, windowHeight: 760)
        XCTAssertEqual(small - large, 100, accuracy: 1)
    }
}

@MainActor
final class DictionaryResizeHandleTests: XCTestCase {
    private func mouseEvent(_ type: NSEvent.EventType, y: CGFloat) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: NSPoint(x: 100, y: y),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }

    private func handle(height: CGFloat, available: CGFloat) -> DictionaryResizeView {
        let view = DictionaryResizeView()
        view.displayedHeight = height
        view.available = available
        return view
    }

    /// The panel moves when its background is dragged, so the handle must
    /// refuse that drag or the resize never starts.
    func testHandleDoesNotMoveTheWindow() {
        let view = handle(height: 150, available: 600)
        XCTAssertFalse(view.mouseDownCanMoveWindow)
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
    }

    func testDraggingUpGrowsThePaneAndStoresTheResult() throws {
        let view = handle(height: 150, available: 600)
        var dragged: [CGFloat] = []
        var ended: CGFloat?
        view.onDrag = { dragged.append($0) }
        view.onEnd = { ended = $0 }

        // Window coordinates point up, so a drag upwards increases y.
        view.mouseDown(with: try mouseEvent(.leftMouseDown, y: 300))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, y: 340))
        XCTAssertEqual(dragged.last, 190)

        view.mouseUp(with: try mouseEvent(.leftMouseUp, y: 340))
        XCTAssertEqual(ended, 190)
    }

    func testDraggingDownShrinksThePaneOnlyToItsMinimum() throws {
        let view = handle(height: 150, available: 600)
        var ended: CGFloat?
        view.onEnd = { ended = $0 }

        view.mouseDown(with: try mouseEvent(.leftMouseDown, y: 300))
        view.mouseDragged(with: try mouseEvent(.leftMouseDragged, y: -900))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, y: -900))

        XCTAssertEqual(ended, DictionaryPaneLayout.minimumHeight)
    }
}
