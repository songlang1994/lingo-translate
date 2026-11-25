import AppKit
import SwiftUI

final class TranslationPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController {
    let panel: TranslationPanel

    private let model: TranslatorModel
    private var escapeMonitor: Any?
    private var previousApp: NSRunningApplication?
    private(set) var shownAt: Date?

    init(model: TranslatorModel, openSettings: @escaping () -> Void) {
        self.model = model

        let size = NSSize(width: 640, height: 420)
        panel = TranslationPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView, .resizable, .closable],
            backing: .buffered,
            defer: false
        )

        let root = TranslatorView(model: model, openSettings: openSettings)
        panel.contentView = NSHostingView(rootView: root)

        panel.level = .floating
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isRestorable = false
        panel.minSize = NSSize(width: 420, height: 260)

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

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event) ?? event
        }
    }

    deinit {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
    }

    func toggle() {
        if panel.isVisible && panel.isKeyWindow {
            hide()
        } else {
            show()
        }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication

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

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        shownAt = Date()
        model.requestFocus()
    }

    func hide(returnFocus: Bool = true) {
        guard panel.isVisible else { return }
        panel.orderOut(nil)

        if returnFocus {
            if let previousApp, previousApp != NSRunningApplication.current {
                previousApp.activate()
            } else {
                NSApp.hide(nil)
            }
        }
        previousApp = nil
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard panel.isKeyWindow else { return event }

        if event.keyCode == 53 {
            hide()
            return nil
        }

        if event.keyCode == 36 || event.keyCode == 76 {
            if event.modifierFlags.contains(.command) {
                model.translateNow()
                return nil
            }
        }

        return event
    }
}
