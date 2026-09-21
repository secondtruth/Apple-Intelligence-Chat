//
//  ChatMessage.swift
//  Apple Intelligence Chat
//

import Foundation

/// Represents the role of a chat participant.
enum ChatRole: String, Codable, Sendable {
    case user
    case assistant
}

/// A single message in a conversation.
struct ChatMessage: Identifiable, Equatable, Codable, Sendable {
    var id: UUID = UUID()
    var role: ChatRole
    var text: String
    var createdAt: Date = .now

    /// Populated when generation failed, so the bubble can offer a retry.
    var failure: String?

    init(id: UUID = UUID(), role: ChatRole, text: String, createdAt: Date = .now, failure: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.failure = failure
    }
}
