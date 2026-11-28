import AppKit
import Carbon.HIToolbox
import SwiftUI

final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// A click while another window holds key would otherwise be spent on the
    /// key-window transfer, so the first click never reaches the control under
    /// the pointer.
    override func sendEvent(_ event: NSEvent) {
        if !isKeyWindow, event.type == .leftMouseDown || event.type == .rightMouseDown {
            makeKey()
        }
        super.sendEvent(event)
    }
}

@MainActor
final class PanelController {
    let panel: TranslationPanel

    var isVisible: Bool { panel.isVisible }

    private let model: TranslatorModel
    private var localKeyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var frontmostAppObserver: NSObjectProtocol?
    private var resignKeyObserver: NSObjectProtocol?
    private var focusCheckWorkItems: [DispatchWorkItem] = []

    /// The app macOS put in front before we fell back to activating ourselves.
    private var previouslyActiveApp: NSRunningApplication?
    /// The app that was last frontmost before Lingo, with the moment Lingo took
    /// the foreground. Clicking our status item activates the app, so the
    /// selection has to come from this app when we are already frontmost.
    private var lastExternalApp: NSRunningApplication?
    private var lastExternalAppLeftAt: Date = .distantPast
    private static let selectionSourceWindow: TimeInterval = 2
    /// True once we gave up on the non-activating route and activated Lingo.
    private var didActivate = false
    /// Right after showing, macOS may briefly grant key status and then take it
    /// back when the request came from a background app. Focus changes inside
    /// this window are the system settling, not the user leaving.
    private var focusSettlesAt: Date = .distantPast

    init(model: TranslatorModel, openSettings: @escaping () -> Void) {
        self.model = model

        let size = NSSize(width: 800, height: 480)
        panel = TranslationPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable, .closable],
            backing: .buffered,
            defer: false
        )

        let root = TranslatorView(model: model, openSettings: openSettings)
        panel.contentView = NSHostingView(rootView: root)

        panel.level = .floating
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isRestorable = false
        panel.minSize = NSSize(width: 560, height: 280)

        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 14
        panel.contentView?.layer?.masksToBounds = true

        if panel.setFrameUsingName("TranslationPanel") == false, let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2 + visible.height * 0.08
            ))
        }
        panel.setFrameAutosaveName("TranslationPanel")

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Writing this as `self?.handleKeyDown(event) ?? event` would flatten
            // the optional: a nil return from handleKeyDown becomes nil for the
            // whole chain, so `??` restores the event and nothing is consumed.
            guard let self else { return event }
            return self.handleKeyDown(event)
        }

        frontmostAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.handleFrontmostAppChange(note)
            }
        }

        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePanelResignedKey()
            }
        }
    }

    deinit {
        focusCheckWorkItems.forEach { $0.cancel() }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        if let frontmostAppObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(frontmostAppObserver)
        }
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
        }
    }

    func toggle() {
        if panel.isVisible && panel.isKeyWindow {
            hide()
        } else {
            show()
        }
    }

    func show(fillSelection: Bool = true) {
        cancelFocusChecks()
        didActivate = false
        focusSettlesAt = Date().addingTimeInterval(3.0)

        let frontmost = NSWorkspace.shared.frontmostApplication
        let sourceApp = frontmost.flatMap { $0 == NSRunningApplication.current ? nil : $0 } ?? recentExternalApp()
        previouslyActiveApp = frontmost.flatMap { $0 == NSRunningApplication.current ? nil : $0 }
        if fillSelection, let sourceApp {
            // Must run while the other app still owns the selection.
            fillSelectionFrom(sourceApp)
        }

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            var frame = panel.frame
            let wasOffscreen = !visible.intersects(frame)
            if wasOffscreen {
                frame.origin = NSPoint(
                    x: visible.midX - frame.width / 2,
                    y: visible.midY - frame.height / 2 + visible.height * 0.1
                )
                panel.setFrame(frame, display: false)
            }
        }

        // Spotlight-style: take the keyboard without activating the app, so the
        // frontmost app, its menu bar and its Spaces stay exactly as they were.
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        model.requestFocus()

        startOutsideClickMonitor()
        scheduleFocusChecks()
    }

    func hide(returnFocus: Bool = true) {
        guard panel.isVisible else { return }
        cancelFocusChecks()
        panel.orderOut(nil)
        stopOutsideClickMonitor()

        let wasActive = NSApp.isActive
        let hadActivated = didActivate
        didActivate = false
        if returnFocus, hadActivated, let previouslyActiveApp, !previouslyActiveApp.isTerminated {
            previouslyActiveApp.activate()
        } else if wasActive {
            // Leaving a menu-bar app frontmost with no window would strand the
            // menu bar and swallow the next keystrokes, so hand the foreground
            // back in every case where we held it.
            NSApp.hide(nil)
        }
        previouslyActiveApp = nil
    }

    // MARK: - Keyboard

    enum KeyAction: Equatable {
        case hide
        case translate
        case none
    }

    /// ⌘W and ⌘Q hide the panel instead of closing the window or quitting.
    static func keyAction(for event: NSEvent) -> KeyAction {
        if event.keyCode == 53 { return .hide }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command,
           event.keyCode == UInt16(kVK_ANSI_W) || event.keyCode == UInt16(kVK_ANSI_Q) {
            return .hide
        }

        if event.keyCode == 36 || event.keyCode == 76,
           event.modifierFlags.contains(.command) {
            return .translate
        }

        return .none
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard panel.isKeyWindow else { return event }

        switch Self.keyAction(for: event) {
        case .hide:
            hide()
            return nil
        case .translate:
            model.translateNow()
            return nil
        case .none:
            return event
        }
    }

    // MARK: - Selection

    private func fillSelectionFrom(_ app: NSRunningApplication) {
        guard let text = SelectedTextReader.selectedText(in: app) else { return }
        model.prefill(text)
    }

    // MARK: - Dismissal

    /// Clicks in any other application dismiss the panel. A global monitor also
    /// reports clicks that land on this panel: because the panel never
    /// activates the app, the system does not attribute those clicks to us.
    private func startOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            let windowNumber = event.windowNumber
            let point = NSEvent.mouseLocation
            DispatchQueue.main.async {
                guard let self else { return }
                guard !Self.isClickInsidePanel(
                    windowNumber: windowNumber,
                    panelWindowNumber: self.panel.windowNumber,
                    point: point,
                    panelFrame: self.panel.frame
                ) else { return }
                self.hide(returnFocus: false)
            }
        }
    }

    /// Whether a click reported by the global monitor belongs to the panel
    /// itself. `point` is in screen coordinates, like `NSEvent.mouseLocation`.
    nonisolated static func isClickInsidePanel(
        windowNumber: Int,
        panelWindowNumber: Int,
        point: NSPoint,
        panelFrame: NSRect
    ) -> Bool {
        if windowNumber != 0 { return windowNumber == panelWindowNumber }
        return panelFrame.contains(point)
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    private func handleFrontmostAppChange(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if app == NSRunningApplication.current {
            lastExternalAppLeftAt = Date()
            // Taking the foreground ourselves, for example when the window
            // drag activates the app, is not the user leaving the panel.
            return
        }
        lastExternalApp = app
        guard panel.isVisible else { return }
        guard Date() >= focusSettlesAt else { return }
        hide(returnFocus: false)
    }

    /// The app that just lost the foreground to us, if it did so very recently.
    private func recentExternalApp() -> NSRunningApplication? {
        guard Date().timeIntervalSince(lastExternalAppLeftAt) <= Self.selectionSourceWindow,
              let app = lastExternalApp,
              !app.isTerminated
        else { return nil }
        return app
    }

    /// Losing key status while still on screen means either the user moved to
    /// another app, or macOS revoked the keyboard grant it had given a
    /// background app. Only the latter should promote us to a real activation.
    private func handlePanelResignedKey() {
        guard panel.isVisible else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible, !self.panel.isKeyWindow else { return }

            if NSWorkspace.shared.frontmostApplication == NSRunningApplication.current {
                // Another window of ours legitimately holds the keyboard.
                return
            }

            if Date() < self.focusSettlesAt {
                // The system took back the grant given to a background app;
                // activating keeps the panel typeable.
                self.activateForKeyboard()
            } else {
                self.hide(returnFocus: false)
            }
        }
    }

    // MARK: - Focus fallback

    /// macOS may grant key status to a non-activating panel and then take it
    /// back when the request did not come from a user activation. Sampling the
    /// key status for a moment after showing catches that case.
    private func scheduleFocusChecks() {
        for delay in [0.15, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5] {
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.panel.isVisible else { return }
                if !self.panel.isKeyWindow {
                    self.activateForKeyboard()
                }
            }
            focusCheckWorkItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    private func cancelFocusChecks() {
        focusCheckWorkItems.forEach { $0.cancel() }
        focusCheckWorkItems.removeAll()
    }

    /// Fallback for when staying non-activating would leave the panel unable to
    /// receive typing: activate Lingo and remember whom to hand focus back to.
    private func activateForKeyboard() {
        guard panel.isVisible, !didActivate else { return }
        didActivate = true
        previouslyActiveApp = NSWorkspace.shared.frontmostApplication.flatMap {
            $0 == NSRunningApplication.current ? nil : $0
        } ?? previouslyActiveApp
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        model.requestFocus()

        // Activation is asynchronous on macOS 14+, so key status can land a
        // moment after the activate call.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.panel.isVisible, !self.panel.isKeyWindow else { return }
            self.panel.makeKey()
        }
    }
}
