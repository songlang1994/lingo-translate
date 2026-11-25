import AppKit

/// Watches for a double tap of a single modifier key in any application.
final class DoubleTapModifierMonitor {
    private let modifier: NSEvent.ModifierFlags
    private let onTrigger: () -> Void
    private var detector = DoubleTapModifierDetector()
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(modifier: NSEvent.ModifierFlags, onTrigger: @escaping () -> Void) {
        self.modifier = modifier
        self.onTrigger = onTrigger
    }

    deinit {
        stop()
    }

    var isRunning: Bool {
        globalMonitor != nil || localMonitor != nil
    }

    /// Returns false when the process is not allowed to monitor global key events.
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        guard AccessibilityPermission.isGranted else { return false }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            // Global monitor callbacks may arrive off the main thread.
            let type = event.type
            let keyCode = event.keyCode
            let modifierFlags = event.modifierFlags
            let timestamp = event.timestamp
            DispatchQueue.main.async {
                self?.handle(type: type, keyCode: keyCode, modifierFlags: modifierFlags, timestamp: timestamp)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handle(
                type: event.type,
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags,
                timestamp: event.timestamp
            )
            return event
        }

        return isRunning
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        detector.reset()
    }

    private func handle(
        type: NSEvent.EventType,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        timestamp: TimeInterval
    ) {
        switch type {
        case .flagsChanged:
            let triggeredModifier = detector.handleFlagsChanged(
                keyCode: keyCode,
                modifierFlags: modifierFlags,
                at: timestamp
            )
            if triggeredModifier == modifier {
                onTrigger()
            }
        case .keyDown:
            detector.handleKeyDown()
        default:
            break
        }
    }
}
