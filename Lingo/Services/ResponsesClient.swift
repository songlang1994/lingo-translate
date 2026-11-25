import Foundation

private struct RequestBody: Encodable {
    let model: String
    let instructions: String
    let input: String
    var stream: Bool
}

enum ResponsesError: LocalizedError {
    case notConfigured
    case emptyResponse
    case http(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Set the endpoint, model, and API key in Settings."
        case .emptyResponse:
            return "The model returned an empty translation."
        case let .http(status, message):
            return message.isEmpty ? "Request failed with HTTP \(status)." : message
        }
    }
}

final class ResponsesClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 300
        configuration.httpAdditionalHeaders = ["User-Agent": "Lingo/1.0"]
        session = URLSession(configuration: configuration)
    }

    @MainActor
    func translate(
        _ text: String,
        from source: Language,
        to target: Language,
        configuration: Configuration,
        onDelta: @escaping (String) -> Void
    ) async throws -> String {
        guard configuration.isConfigured, let url = configuration.url else {
            throw ResponsesError.notConfigured
        }

        let body = RequestBody(
            model: configuration.model.trimmingCharacters(in: .whitespacesAndNewlines),
            instructions: Prompt.instructions(source: source, target: target),
            input: text,
            stream: true
        )

        do {
            return try await stream(body: body, url: url, apiKey: configuration.apiKey, onDelta: onDelta)
        } catch ResponsesError.emptyResponse {
            var fallback = body
            fallback.stream = false
            return try await send(body: fallback, url: url, apiKey: configuration.apiKey)
        }
    }

    @MainActor
    private func stream(
        body: RequestBody,
        url: URL,
        apiKey: String,
        onDelta: @escaping (String) -> Void
    ) async throws -> String {
        var request = try makeRequest(body: body, url: url, apiKey: apiKey)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ResponsesError.http(status: -1, message: "Unexpected response.")
        }

        guard (200..<300).contains(http.statusCode) else {
            let data = try await collect(from: bytes, limit: 65_536)
            throw ResponsesError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        guard contentType.contains("text/event-stream") else {
            let data = try await collect(from: bytes, limit: 4_000_000)
            return try Self.parseResponse(data)
        }

        var streamed = ""
        var finishedText: String?

        for try await rawLine in bytes.lines {
            if Task.isCancelled { throw CancellationError() }

            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("data:") else { continue }

            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload.isEmpty || payload == "[DONE]" { continue }

            guard let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }

            switch type {
            case "response.output_text.delta":
                if let delta = event["delta"] as? String {
                    streamed += delta
                    onDelta(delta)
                }
            case "response.output_text.done":
                if let text = event["text"] as? String { finishedText = text }
            case "response.completed":
                if let response = event["response"] as? [String: Any],
                   let text = Self.extractText(from: response) {
                    finishedText = text
                }
            case "response.failed":
                let error = (event["response"] as? [String: Any])?["error"] as? [String: Any]
                let message = error?["message"] as? String ?? "The response failed."
                throw ResponsesError.http(status: 200, message: message)
            case "error":
                let message = event["message"] as? String ?? "The server returned an error."
                throw ResponsesError.http(status: 200, message: message)
            default:
                break
            }
        }

        let result = streamed.isEmpty ? (finishedText ?? "") : streamed
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ResponsesError.emptyResponse
        }
        return result
    }

    @MainActor
    private func send(body: RequestBody, url: URL, apiKey: String) async throws -> String {
        var request = try makeRequest(body: body, url: url, apiKey: apiKey)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ResponsesError.http(status: -1, message: "Unexpected response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ResponsesError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }
        return try Self.parseResponse(data)
    }

    private func makeRequest(body: RequestBody, url: URL, apiKey: String) throws -> URLRequest {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        var key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.lowercased().hasPrefix("bearer ") {
            key = String(key.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func collect(from bytes: URLSession.AsyncBytes, limit: Int) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit { break }
        }
        return data
    }

    private static func parseResponse(_ data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ResponsesError.http(status: -1, message: "The server returned an invalid response.")
        }
        if let text = extractText(from: root), !text.isEmpty {
            return text
        }
        if let error = root["error"] as? [String: Any], let message = error["message"] as? String {
            throw ResponsesError.http(status: -1, message: message)
        }
        throw ResponsesError.emptyResponse
    }

    private static func extractText(from root: [String: Any]) -> String? {
        if let text = root["output_text"] as? String, !text.isEmpty {
            return text
        }

        if let output = root["output"] as? [[String: Any]] {
            var pieces: [String] = []
            for item in output {
                guard item["type"] as? String == "message" else { continue }
                for part in item["content"] as? [[String: Any]] ?? [] {
                    if part["type"] as? String == "output_text",
                       let text = part["text"] as? String {
                        pieces.append(text)
                    }
                }
            }
            if !pieces.isEmpty { return pieces.joined() }
        }

        if let choices = root["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String,
           !content.isEmpty {
            return content
        }

        return nil
    }

    private static func errorMessage(from data: Data) -> String {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = root["error"] as? [String: Any],
               let message = error["message"] as? String {
                return message
            }
            if let message = root["message"] as? String {
                return message
            }
        }

        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String(raw.prefix(500))
    }
}
