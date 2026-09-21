//
//  ChatEngine.swift
//  Apple Intelligence Chat
//

import Foundation
import Observation

/// Runs a prompt against the selected provider and writes the answer into the
/// store as it arrives. Views call `send`; everything about streaming,
/// cancellation and failure lives here.
@MainActor
@Observable
final class ChatEngine {
    private(set) var respondingConversationID: Conversation.ID?

    private let store: ConversationStore
    private let registry: ProviderRegistry
    private var task: Task<Void, Never>?

    init(store: ConversationStore, registry: ProviderRegistry) {
        self.store = store
        self.registry = registry

        // Changed instructions invalidate the on-device sessions that baked
        // them in.
        registry.instructionsDidChange = { [weak registry, weak store] in
            guard let registry, let store else { return }
            for conversation in store.conversations {
                registry.apple.forget(conversation: conversation.id)
            }
        }
    }

    var isResponding: Bool { respondingConversationID != nil }

    func isResponding(in id: Conversation.ID) -> Bool {
        respondingConversationID == id
    }

    // MARK: - Sending

    func send(_ text: String, in id: Conversation.ID) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isResponding else { return }
        store.append(ChatMessage(role: .user, text: prompt), to: id)
        run(in: id)
    }

    /// Drops the last answer and asks again — for a reply that was cut off,
    /// failed, or simply missed the point.
    func regenerate(in id: Conversation.ID) {
        guard !isResponding, let conversation = store.conversations.first(where: { $0.id == id }) else { return }

        for message in conversation.messages.reversed() {
            guard message.role == .assistant else { break }
            store.removeMessage(message.id, in: id)
        }
        guard store.conversations.first(where: { $0.id == id })?.messages.last?.role == .user else { return }

        // The cached session already holds the answer we just discarded.
        registry.current.forget(conversation: id)
        run(in: id)
    }

    func stop() {
        task?.cancel()
    }

    private func run(in id: Conversation.ID) {
        guard let conversation = store.conversations.first(where: { $0.id == id }) else { return }

        let placeholder = ChatMessage(role: .assistant, text: "")
        store.append(placeholder, to: id)
        respondingConversationID = id

        let request = ChatRequest(
            conversationID: id,
            history: conversation.messages,
            settings: registry.settings)
        let provider = registry.current

        task = Task { [store] in
            var accumulated = ""
            var cancelled = false

            do {
                for try await chunk in provider.stream(request) {
                    switch chunk {
                    case .delta(let delta): accumulated += delta
                    case .replace(let text): accumulated = text
                    }
                    store.updateMessage(placeholder.id, in: id) { $0.text = accumulated }
                }
            } catch is CancellationError {
                cancelled = true
            } catch {
                store.updateMessage(placeholder.id, in: id) { message in
                    message.failure = error.localizedDescription
                }
            }

            // A cancelled or empty answer leaves no bubble behind.
            if accumulated.isEmpty,
               store.conversations.first(where: { $0.id == id })?
                   .messages.first(where: { $0.id == placeholder.id })?.failure == nil {
                if cancelled {
                    store.removeMessage(placeholder.id, in: id)
                } else {
                    store.updateMessage(placeholder.id, in: id) { message in
                        message.failure = String(localized: "The model returned nothing.")
                    }
                }
            }

            store.finishExchange(in: id)
            respondingConversationID = nil
            task = nil
        }
    }
}
