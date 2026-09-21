//
//  ChatProvider.swift
//  Apple Intelligence Chat
//

import Foundation

/// Which backend answers a prompt.
enum ProviderKind: String, CaseIterable, Identifiable, Codable, Sendable {
    /// The on-device model via the Foundation Models framework.
    case appleIntelligence
    /// Any server speaking the OpenAI chat-completions API — Ollama, llama.cpp,
    /// LM Studio, a hosted endpoint.
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleIntelligence: String(localized: "Apple Intelligence")
        case .openAICompatible: String(localized: "Ollama / OpenAI-compatible")
        }
    }

    var symbolName: String {
        switch self {
        case .appleIntelligence: "sparkles"
        case .openAICompatible: "server.rack"
        }
    }
}

/// Knobs that apply to every provider.
struct GenerationSettings: Equatable, Sendable {
    var systemInstructions: String
    var temperature: Double
    var stream: Bool
}

/// What a provider reports about its readiness. The chat pane surfaces the
/// reason verbatim, the way Siri states its own status.
enum ProviderAvailability: Equatable, Sendable {
    case checking
    case available
    case unavailable(reason: String, recovery: String?)

    var isAvailable: Bool { self == .available }
}

/// One generation request. `history` carries the whole thread including the
/// new user message, so stateless providers can send it as-is while stateful
/// ones take only the last turn.
struct ChatRequest: Sendable {
    var conversationID: UUID
    var history: [ChatMessage]
    var settings: GenerationSettings

    var latestPrompt: String {
        history.last(where: { $0.role == .user })?.text ?? ""
    }
}

/// A piece of a streamed answer. Providers differ in what they hand out:
/// the on-device model yields the full text so far, OpenAI-compatible servers
/// yield increments. Making that explicit keeps the view from guessing.
enum StreamChunk: Equatable, Sendable {
    case delta(String)
    case replace(String)
}

enum ProviderError: LocalizedError {
    case notConfigured(String)
    case server(status: Int, message: String)
    case transport(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let detail): detail
        case .server(let status, let message): "The server answered \(status): \(message)"
        case .transport(let detail): detail
        case .decoding(let detail): "Unreadable response: \(detail)"
        }
    }
}

@MainActor
protocol ChatProvider: AnyObject {
    var kind: ProviderKind { get }

    /// Re-checks readiness; called on launch, on settings changes and when the
    /// user retries a failed message.
    func refreshAvailability() async -> ProviderAvailability

    /// Model identifiers the backend offers, empty when it has no choice to make.
    func availableModels() async -> [String]

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamChunk, Error>

    /// Drops any cached session for a conversation, after a reset or an
    /// instruction change.
    func forget(conversation id: UUID)
}
