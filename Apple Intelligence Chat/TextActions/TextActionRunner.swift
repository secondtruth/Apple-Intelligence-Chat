//
//  TextActionRunner.swift
//  Apple Intelligence Chat
//

import Foundation

/// Runs one text action to completion. Separate from ChatEngine because these
/// requests have no conversation, no history and no streaming — a single
/// transformation in and out.
@MainActor
final class TextActionRunner {
    private let registry: ProviderRegistry
    private let library: PromptLibrary

    init(registry: ProviderRegistry, library: PromptLibrary) {
        self.registry = registry
        self.library = library
    }

    enum RunError: LocalizedError {
        case emptySelection
        case providerUnavailable(String)
        case empty

        var errorDescription: String? {
            switch self {
            case .emptySelection: String(localized: "There was no text to work on.")
            case .providerUnavailable(let reason): reason
            case .empty: String(localized: "The model returned nothing.")
            }
        }
    }

    /// A free-form question with no conversation behind it — what the quick-ask
    /// panel sends. Streams so the panel fills as the answer arrives.
    func ask(_ question: String, onDelta: @escaping (String) -> Void) async throws -> String {
        let prompt = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { throw RunError.emptySelection }

        if case .unavailable(let reason, let recovery) = registry.availability {
            throw RunError.providerUnavailable([reason, recovery].compactMap { $0 }.joined(separator: " "))
        }

        let request = ChatRequest(
            conversationID: UUID(),
            history: [ChatMessage(role: .user, text: prompt)],
            settings: registry.settings)

        let provider = registry.current
        defer { provider.forget(conversation: request.conversationID) }

        var output = ""
        for try await chunk in provider.stream(request) {
            switch chunk {
            case .delta(let delta): output += delta
            case .replace(let whole): output = whole
            }
            onDelta(output)
        }

        let result = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw RunError.empty }
        return result
    }

    func run(_ role: TextActionRole, on selection: String) async throws -> String {
        let text = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw RunError.emptySelection }

        if case .unavailable(let reason, let recovery) = registry.availability {
            throw RunError.providerUnavailable([reason, recovery].compactMap { $0 }.joined(separator: " "))
        }

        let prompt = library.prompt(for: role)
        let request = ChatRequest(
            conversationID: UUID(),
            history: [ChatMessage(role: .user, text: prompt.rendered(with: text))],
            settings: GenerationSettings(
                instructionsOverride: prompt.instructions,
                base: registry.settings))

        let provider = registry.current
        defer { provider.forget(conversation: request.conversationID) }

        var output = ""
        for try await chunk in provider.stream(request) {
            switch chunk {
            case .delta(let delta): output += delta
            case .replace(let whole): output = whole
            }
        }

        let result = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw RunError.empty }
        return result
    }
}

extension GenerationSettings {
    /// A text action borrows the user's temperature but brings its own
    /// instructions, and never streams — the caller needs one finished string.
    init(instructionsOverride: String, base: GenerationSettings) {
        self.init(
            systemInstructions: instructionsOverride,
            temperature: base.temperature,
            stream: false)
    }
}
