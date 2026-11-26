import AppKit

@main
struct LingoMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        // Unit tests are hosted in the app; skip hot keys, the status item, and windows.
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
        let delegate = isRunningTests ? nil : AppDelegate()
        application.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}
