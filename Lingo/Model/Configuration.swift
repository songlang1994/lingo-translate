import Foundation

/// How much internal reasoning the model may spend before answering.
/// Sent as `reasoning.effort` on the Responses API.
enum ReasoningEffort: String, CaseIterable, Identifiable {
    /// Omits the field so the server default applies.
    case automatic = ""
    case none
    case minimal
    case low
    case medium
    case high

    var id: String { rawValue }

    var requestValue: String? {
        self == .automatic ? nil : rawValue
    }

    var title: String {
        switch self {
        case .automatic: return "Default"
        case .none: return "None"
        case .minimal: return "Minimal"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

struct Configuration: Equatable {
    var endpoint: String
    var apiKey: String
    var model: String
    var reasoningEffort: ReasoningEffort = .none

    /// Resolves the configured endpoint into the URL that actually receives requests.
    /// Base addresses such as `https://api.example.com` or `https://api.example.com/v1`
    /// are expanded to `https://api.example.com/v1/responses`.
    var url: URL? {
        var text = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if !text.contains("://") {
            text = (Self.looksLocal(text) ? "http://" : "https://") + text
        }

        while text.hasSuffix("/") {
            text.removeLast()
        }

        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host,
              !host.isEmpty else {
            return nil
        }

        let path = components.path
        if path.isEmpty {
            components.path = "/v1/responses"
        } else if path.lowercased().hasSuffix("/v1") {
            components.path = path + "/responses"
        }

        return components.url
    }

    var isLocalEndpoint: Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local")
    }

    private static func looksLocal(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("localhost") || lower.hasPrefix("127.0.0.1") || lower.hasPrefix("[::1]")
    }

    var isConfigured: Bool {
        guard url != nil, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return isLocalEndpoint || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
