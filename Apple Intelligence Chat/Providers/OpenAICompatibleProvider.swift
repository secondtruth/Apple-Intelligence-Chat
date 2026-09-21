//
//  OpenAICompatibleProvider.swift
//  Apple Intelligence Chat
//

import Foundation

/// Speaks the OpenAI chat-completions API, which is what Ollama, llama.cpp,
/// LM Studio and hosted endpoints all expose. One client reaches every one of
/// them; only the base URL, model and key differ.
@MainActor
final class OpenAICompatibleProvider: ChatProvider {
    struct Configuration: Equatable, Sendable {
        var baseURL: String
        var apiKey: String
        var model: String

        static let ollamaDefault = Configuration(
            baseURL: "http://localhost:11434/v1",
            apiKey: "",
            model: "")

        /// Trailing slashes are the most common paste error, so they are
        /// tolerated rather than turned into a 404.
        var normalizedBaseURL: URL? {
            var text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            while text.hasSuffix("/") { text.removeLast() }
            guard !text.isEmpty else { return nil }
            return URL(string: text)
        }

        func endpoint(_ path: String) -> URL? {
            normalizedBaseURL?.appendingPathComponent(path)
        }
    }

    let kind: ProviderKind = .openAICompatible
    var configuration: Configuration

    private let session: URLSession

    init(configuration: Configuration = .ollamaDefault) {
        self.configuration = configuration
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    func forget(conversation id: UUID) {}

    // MARK: - Availability

    func refreshAvailability() async -> ProviderAvailability {
        guard let url = configuration.endpoint("models") else {
            return .unavailable(
                reason: String(localized: "The server address is not a valid URL."),
                recovery: String(localized: "Set it in Settings, for example http://localhost:11434/v1"))
        }

        do {
            _ = try await fetchModels(from: url)
        } catch let error as ProviderError {
            return .unavailable(reason: error.localizedDescription, recovery: recoveryHint())
        } catch {
            return .unavailable(reason: error.localizedDescription, recovery: recoveryHint())
        }

        guard !configuration.model.isEmpty else {
            return .unavailable(
                reason: String(localized: "No model selected."),
                recovery: String(localized: "Pick one from the model menu."))
        }
        return .available
    }

    private func recoveryHint() -> String {
        let host = configuration.normalizedBaseURL?.host ?? "localhost"
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return String(localized: "Start the server with `ollama serve`, then try again.")
        }
        return String(localized: "Check that the server is reachable and allows this Mac.")
    }

    func availableModels() async -> [String] {
        (try? await listModels()) ?? []
    }

    /// The server's catalogue, or the reason it could not be read — what
    /// Settings shows about a server that is not the selected answerer.
    func listModels() async throws -> [String] {
        guard let url = configuration.endpoint("models") else {
            throw ProviderError.notConfigured(String(localized: "The server address is not a valid URL."))
        }
        return try await fetchModels(from: url)
    }

    private func fetchModels(from url: URL) async throws -> [String] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        authorize(&request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ProviderError.transport(error.localizedDescription)
        }

        try Self.validate(response: response, body: data)

        struct ModelList: Decodable {
            struct Entry: Decodable { let id: String }
            // Ollama answers an empty catalogue with "data": null rather than
            // an empty array, so this must tolerate the missing list.
            let data: [Entry]?
        }
        do {
            return try JSONDecoder().decode(ModelList.self, from: data).data?
                .map(\.id)
                .sorted() ?? []
        } catch {
            throw ProviderError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Streaming

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try makeCompletionRequest(for: request)
                    if request.settings.stream {
                        try await streamCompletion(urlRequest, into: continuation)
                    } else {
                        try await completeOnce(urlRequest, into: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeCompletionRequest(for request: ChatRequest) throws -> URLRequest {
        guard let url = configuration.endpoint("chat/completions") else {
            throw ProviderError.notConfigured(String(localized: "The server address is not a valid URL."))
        }
        guard !configuration.model.isEmpty else {
            throw ProviderError.notConfigured(String(localized: "No model selected. Pick one from the model menu."))
        }

        var payload: [String: Any] = [
            "model": configuration.model,
            "stream": request.settings.stream,
            "temperature": request.settings.temperature,
            "messages": messages(for: request),
        ]
        if request.settings.stream {
            // Ollama only reports token counts when asked.
            payload["stream_options"] = ["include_usage": false]
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)
        authorize(&urlRequest)
        return urlRequest
    }

    private func messages(for request: ChatRequest) -> [[String: String]] {
        var messages: [[String: String]] = []
        let instructions = request.settings.systemInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty {
            messages.append(["role": "system", "content": instructions])
        }
        for message in request.history where !message.text.isEmpty {
            messages.append(["role": message.role.rawValue, "content": message.text])
        }
        return messages
    }

    private func authorize(_ request: inout URLRequest) {
        let key = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    }

    private func streamCompletion(
        _ request: URLRequest,
        into continuation: AsyncThrowingStream<StreamChunk, Error>.Continuation
    ) async throws {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw ProviderError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var body = ""
            for try await line in bytes.lines where body.count < 2_000 {
                body += line
            }
            throw ProviderError.server(status: http.statusCode, message: Self.humanReadable(body))
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let chunk = Self.parse(line: line) else { continue }
            switch chunk {
            case .done: return
            case .text(let text): continuation.yield(.delta(text))
            }
        }
    }

    private func completeOnce(
        _ request: URLRequest,
        into continuation: AsyncThrowingStream<StreamChunk, Error>.Continuation
    ) async throws {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ProviderError.transport(error.localizedDescription)
        }
        try Self.validate(response: response, body: data)

        struct Completion: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message?
            }
            let choices: [Choice]
        }
        do {
            let completion = try JSONDecoder().decode(Completion.self, from: data)
            continuation.yield(.replace(completion.choices.first?.message?.content ?? ""))
        } catch {
            throw ProviderError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Server-sent events

    private enum ParsedLine {
        case text(String)
        case done
    }

    private static func parse(line: String) -> ParsedLine? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return nil }

        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return nil }
        guard payload != "[DONE]" else { return .done }

        struct Chunk: Decodable {
            struct Choice: Decodable {
                struct Delta: Decodable { let content: String? }
                let delta: Delta?
            }
            let choices: [Choice]
        }
        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(Chunk.self, from: data),
              let content = chunk.choices.first?.delta?.content,
              !content.isEmpty
        else { return nil }
        return .text(content)
    }

    private static func validate(response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }
        let text = String(data: body, encoding: .utf8) ?? ""
        throw ProviderError.server(status: http.statusCode, message: humanReadable(text))
    }

    /// Servers wrap their complaint in `{"error": {"message": "..."}}`; showing
    /// the raw JSON in an alert helps nobody.
    private static func humanReadable(_ body: String) -> String {
        guard let data = body.data(using: .utf8) else { return body }

        struct Wrapper: Decodable {
            struct Detail: Decodable { let message: String? }
            let error: DetailOrString?

            enum DetailOrString: Decodable {
                case detail(Detail)
                case text(String)

                init(from decoder: Decoder) throws {
                    let container = try decoder.singleValueContainer()
                    if let text = try? container.decode(String.self) {
                        self = .text(text)
                    } else {
                        self = .detail(try container.decode(Detail.self))
                    }
                }

                var message: String? {
                    switch self {
                    case .detail(let detail): detail.message
                    case .text(let text): text
                    }
                }
            }
        }

        if let wrapper = try? JSONDecoder().decode(Wrapper.self, from: data),
           let message = wrapper.error?.message, !message.isEmpty {
            return message
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "no details") : trimmed
    }
}
