import AppKit
import Combine

@MainActor
final class TranslatorModel: ObservableObject {
    @Published var input = ""
    @Published var output = ""
    @Published var isTranslating = false
    @Published var errorMessage: String?
    @Published var copied = false
    @Published var focusToken = 0

    private(set) var sourceCode: String
    private(set) var targetCode: String

    private let settings: AppSettings
    private let client = ResponsesClient()
    private var translationTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var copyTask: Task<Void, Never>?
    private var programmaticInput: String?
    private var requestID = 0

    init(settings: AppSettings) {
        self.settings = settings
        sourceCode = settings.sourceCode
        targetCode = settings.targetCode
    }

    var sourceLanguage: Language { Language.named(sourceCode) }
    var targetLanguage: Language { Language.named(targetCode) }

    var canCopy: Bool {
        !output.isEmpty && errorMessage == nil && !isTranslating
    }

    func requestFocus() {
        focusToken &+= 1
    }

    func prefill(_ text: String) {
        programmaticInput = text
        input = text
        translateNow()
    }

    func inputDidChange() {
        if let programmaticInput, programmaticInput == input {
            self.programmaticInput = nil
            return
        }
        scheduleTranslation()
    }

    func selectSource(_ code: String) {
        guard code != sourceCode else { return }
        sourceCode = code
        settings.sourceCode = code
        scheduleTranslation()
    }

    func selectTarget(_ code: String) {
        guard code != targetCode, code != Language.automatic.code else { return }
        targetCode = code
        settings.targetCode = code
        scheduleTranslation()
    }

    func translateNow() {
        debounceTask?.cancel()
        startTranslation()
    }

    func swapLanguages() {
        let previousSource = Language.named(sourceCode)
        let previousTarget = Language.named(targetCode)

        let newSource = previousTarget
        var newTarget = previousSource.isAutomatic ? Language.defaultTarget : previousSource
        if newTarget == newSource {
            newTarget = newSource.code == "en" ? Language.named("zh-Hans") : Language.named("en")
        }

        guard !newSource.isAutomatic, !newTarget.isAutomatic else { return }

        translationTask?.cancel()
        debounceTask?.cancel()
        requestID += 1
        isTranslating = false
        errorMessage = nil

        sourceCode = newSource.code
        targetCode = newTarget.code
        settings.sourceCode = newSource.code
        settings.targetCode = newTarget.code

        if !output.isEmpty {
            let previousInput = input
            programmaticInput = output
            input = output
            output = previousInput
        } else {
            startTranslation()
        }
    }

    func copyOutput() {
        guard canCopy else { return }
        let text = output

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        copied = true
        copyTask?.cancel()
        copyTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            self?.copied = false
        }
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scheduleTranslation() {
        debounceTask?.cancel()

        guard !trimmedInput.isEmpty else {
            translationTask?.cancel()
            translationTask = nil
            debounceTask = nil
            requestID += 1
            isTranslating = false
            errorMessage = nil
            output = ""
            return
        }

        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.startTranslation()
        }
    }

    private func startTranslation() {
        let text = trimmedInput
        guard !text.isEmpty else { return }

        let source = sourceLanguage
        let target = targetLanguage
        guard !target.isAutomatic else { return }

        let configuration = settings.configuration

        translationTask?.cancel()
        requestID += 1
        let currentRequestID = requestID

        errorMessage = nil
        isTranslating = true
        output = ""

        translationTask = Task { [weak self] in
            guard let self else { return }

            var streamed = ""
            do {
                let result = try await self.client.translate(
                    text,
                    from: source,
                    to: target,
                    configuration: configuration
                ) { delta in
                    guard self.requestID == currentRequestID else { return }
                    streamed += delta
                    self.output = streamed
                }

                guard !Task.isCancelled, self.requestID == currentRequestID else { return }
                self.output = result
                self.isTranslating = false
            } catch {
                guard !Task.isCancelled, self.requestID == currentRequestID else { return }
                self.output = ""
                self.isTranslating = false
                self.errorMessage = Self.message(for: error, configuration: configuration)
            }
        }
    }

    private static func message(for error: Error, configuration: Configuration) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "No network connection."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Cannot reach \(configuration.url?.host ?? "the server")."
            case .timedOut:
                return "The request timed out."
            case .cancelled:
                return ""
            case .appTransportSecurityRequiresSecureConnection:
                return "The endpoint must use HTTPS."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
