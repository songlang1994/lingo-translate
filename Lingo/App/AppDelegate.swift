import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings!
    private var model: TranslatorModel!
    private var panelController: PanelController!
    private var settingsWindow: SettingsWindowController!
    private var hotKeyManager: HotKeyManager!
    private var statusItem: NSStatusItem!
    private var hotKeyFailureObserver: NSObjectProtocol?
    private var panelRestoresAfterSettings = false
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = AppSettings()
        model = TranslatorModel(settings: settings)

        settingsWindow = SettingsWindowController(settings: settings) { [weak self] suspended in
            self?.hotKeyManager?.setSuspended(suspended)
        }
        settingsWindow.onClose = { [weak self] in
            guard let self, !self.isTerminating, self.panelRestoresAfterSettings else { return }
            self.panelRestoresAfterSettings = false
            self.panelController.show(fillSelection: false)
        }

        panelController = PanelController(model: model) { [weak self] in
            self?.openSettings()
        }

        hotKeyManager = HotKeyManager(settings: settings) { [weak self] in
            self?.panelController.toggle()
        }

        setUpStatusItem()
        setUpMenu()

        hotKeyFailureObserver = NotificationCenter.default.addObserver(
            forName: .hotKeyRegistrationFailed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.presentHotKeyFailure()
            }
        }

        if !settings.isReady {
            Task { @MainActor [weak self] in
                self?.settingsWindow.show()
            }
        }

        #if DEBUG
        if CommandLine.arguments.contains("--dark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

        if let index = CommandLine.arguments.firstIndex(of: "--demo-text"),
           CommandLine.arguments.count > index + 1 {
            model.prefill(CommandLine.arguments[index + 1])
        }

        if CommandLine.arguments.contains("--show-panel") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 400_000_000)
                self?.panelController.show()
            }
        }

        if CommandLine.arguments.contains("--show-settings") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 400_000_000)
                self?.openSettings()
            }
        }
        #endif
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isTerminating = true
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        if let hotKeyFailureObserver {
            NotificationCenter.default.removeObserver(hotKeyFailureObserver)
        }
    }

    @objc private func openSettings() {
        panelRestoresAfterSettings = panelController.isVisible
        panelController.hide(returnFocus: false)
        settingsWindow.show()
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            panelController.toggle()
        }
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Lingo Translate")
        image?.isTemplate = true
        button.image = image
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func showStatusMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Lingo Translate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func setUpMenu() {
        let mainMenu = NSMenu()

        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit Lingo Translate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        applicationItem.submenu = applicationMenu

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        mainMenu.addItem(applicationItem)
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func presentHotKeyFailure() {
        let alert = NSAlert()
        alert.messageText = "Shortcut unavailable"
        alert.informativeText = "Another application is already using \(settings.shortcut.display). Choose a different shortcut."
        alert.alertStyle = .warning
        alert.runModal()
    }
}
