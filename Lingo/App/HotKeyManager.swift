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
    private var cancellable: AnyCancellable?
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
    }

    func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        isSuspended = suspended
        if suspended {
            hotKey?.unregister()
            hotKey = nil
        } else {
            register(userInitiated: true)
        }
    }

    @discardableResult
    private func register(userInitiated: Bool = false) -> Bool {
        hotKey?.unregister()
        hotKey = nil

        guard !isSuspended else { return true }

        let registered = GlobalHotKey(shortcut: settings.shortcut) { [weak self] in
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
    }
}
