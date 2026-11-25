import AppKit
import Combine

extension Notification.Name {
    static let hotKeyRegistrationFailed = Notification.Name("Lingo.hotKeyRegistrationFailed")
}

@MainActor
final class HotKeyManager {
    private let settings: AppSettings
    private let onPress: () -> Void
    private var hotKey: GlobalHotKey?
    private var doubleTapMonitor: DoubleTapModifierMonitor?
    private var cancellable: AnyCancellable?
    private var activationObserver: NSObjectProtocol?
    private var isSuspended = false

    init(settings: AppSettings, onPress: @escaping () -> Void) {
        self.settings = settings
        self.onPress = onPress
        register()

        cancellable = settings.$shortcut
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.register(userInitiated: true)
                }
            }

        // Accessibility permission may be granted while the app keeps running.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.retryRegistrationIfNeeded()
            }
        }
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        if suspended {
            tearDownHotKey()
        } else {
            register(userInitiated: true)
        }
    }

    @discardableResult
    private func register(userInitiated: Bool = false) -> Bool {
        tearDownHotKey()

        guard !isSuspended else { return true }

        switch settings.shortcut {
        case let .combination(keyCode, modifiers, _):
            let registered = GlobalHotKey(keyCode: keyCode, modifiers: modifiers) { [weak self] in
                self?.onPress()
            }
            hotKey = registered

            if registered == nil {
                NSLog("Lingo: failed to register shortcut %@", settings.shortcut.display)
                if userInitiated {
                    NotificationCenter.default.post(name: .hotKeyRegistrationFailed, object: nil)
                }
            }
            return registered != nil

        case let .doubleTapModifier(modifier):
            guard AccessibilityPermission.isGranted else {
                NSLog("Lingo: accessibility permission is required for shortcut %@", settings.shortcut.display)
                return false
            }

            let monitor = DoubleTapModifierMonitor(modifier: modifier) { [weak self] in
                self?.onPress()
            }
            guard monitor.start() else {
                NSLog("Lingo: failed to monitor shortcut %@", settings.shortcut.display)
                return false
            }

            doubleTapMonitor = monitor
            return true
        }
    }

    private func retryRegistrationIfNeeded() {
        guard !isSuspended, hotKey == nil, doubleTapMonitor == nil else { return }
        guard settings.shortcut.isDoubleTap, AccessibilityPermission.isGranted else { return }
        register()
    }

    private func tearDownHotKey() {
        hotKey?.unregister()
        hotKey = nil
        doubleTapMonitor?.stop()
        doubleTapMonitor = nil
    }
}
