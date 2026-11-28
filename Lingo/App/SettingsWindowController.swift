import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var hasBeenPositioned = false
    private let settings: AppSettings
    private let suspendHotKey: (Bool) -> Void
    var onClose: (() -> Void)?

    init(settings: AppSettings, suspendHotKey: @escaping (Bool) -> Void) {
        self.settings = settings
        self.suspendHotKey = suspendHotKey
        super.init()
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func show() {
        if window == nil {
            let root = SettingsView(settings: settings, suspendHotKey: suspendHotKey)
            let controller = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: controller)
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.delegate = self
            window.setContentSize(NSSize(width: 460, height: 265))
            self.window = window
        }

        if let window, !hasBeenPositioned, let screen = NSScreen.main {
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: visible.midX - window.frame.width / 2,
                y: visible.midY - window.frame.height / 2
            ))
            hasBeenPositioned = true
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
