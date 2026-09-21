//
//  ConversationStore.swift
//  Apple Intelligence Chat
//

import Foundation
import Observation

/// Owns every conversation and writes them to disk. The store is the single
/// source of truth for the sidebar and the chat pane; views mutate it and
/// never touch the file themselves.
@MainActor
@Observable
final class ConversationStore {
    private(set) var conversations: [Conversation] = []
    var selectedID: Conversation.ID?
    var searchText: String = ""

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }

    // MARK: - Derived state

    var selected: Conversation? {
        guard let selectedID else { return nil }
        return conversations.first { $0.id == selectedID }
    }

    /// Conversations matching the search field, newest first.
    var filtered: [Conversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching: [Conversation]
        if query.isEmpty {
            matching = conversations
        } else {
            matching = conversations.filter { conversation in
                if conversation.title.localizedCaseInsensitiveContains(query) { return true }
                return conversation.messages.contains { $0.text.localizedCaseInsensitiveContains(query) }
            }
        }
        return matching.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Sidebar sections in fixed order, empty ones omitted. Pinned
    /// conversations leave their date section for one at the top.
    var grouped: [(group: ConversationDateGroup, conversations: [Conversation])] {
        let buckets = Dictionary(grouping: filtered) {
            $0.isPinned ? .pinned : ConversationDateGroup.group(for: $0.updatedAt)
        }
        return ConversationDateGroup.allCases.compactMap { group in
            guard let items = buckets[group], !items.isEmpty else { return nil }
            return (group, items)
        }
    }

    // MARK: - Mutations

    @discardableResult
    func newConversation() -> Conversation.ID {
        // Reuse an existing empty draft instead of stacking up "New Chat" rows.
        if let draft = conversations.first(where: { $0.isEmpty }) {
            selectedID = draft.id
            return draft.id
        }
        let conversation = Conversation()
        conversations.insert(conversation, at: 0)
        selectedID = conversation.id
        scheduleSave()
        return conversation.id
    }

    func delete(_ id: Conversation.ID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations.remove(at: index)
        if selectedID == id {
            selectedID = filtered.first?.id
        }
        scheduleSave()
    }

    func deleteAll() {
        conversations.removeAll()
        selectedID = nil
        scheduleSave()
    }

    func togglePin(_ id: Conversation.ID) {
        update(id, touch: false) { $0.pinnedAt = $0.isPinned ? nil : .now }
    }

    func rename(_ id: Conversation.ID, to title: String) {
        update(id) { $0.title = title.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func append(_ message: ChatMessage, to id: Conversation.ID) {
        update(id) { $0.messages.append(message) }
    }

    func updateMessage(_ messageID: ChatMessage.ID, in id: Conversation.ID, transform: (inout ChatMessage) -> Void) {
        update(id, touch: false) { conversation in
            guard let index = conversation.messages.firstIndex(where: { $0.id == messageID }) else { return }
            transform(&conversation.messages[index])
        }
    }

    func removeMessage(_ messageID: ChatMessage.ID, in id: Conversation.ID) {
        update(id) { $0.messages.removeAll { $0.id == messageID } }
    }

    func finishExchange(in id: Conversation.ID) {
        update(id) { $0.deriveTitleIfNeeded() }
    }

    /// Applies a change, moves the conversation to the top of the list and
    /// schedules a write. `touch` is false for streaming updates, which would
    /// otherwise reorder the sidebar on every token.
    private func update(_ id: Conversation.ID, touch: Bool = true, _ transform: (inout Conversation) -> Void) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        transform(&conversations[index])
        if touch { conversations[index].updatedAt = .now }
        scheduleSave()
    }

    // MARK: - Persistence

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        let directory = base.appendingPathComponent("AppleIntelligenceChat", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("conversations.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stored = try? decoder.decode([Conversation].self, from: data) else { return }
        conversations = stored.sorted { $0.updatedAt > $1.updatedAt }
        selectedID = conversations.first?.id
    }

    /// Coalesces the writes that streaming would otherwise trigger per token.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = conversations
        let url = fileURL
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await Self.write(snapshot, to: url)
        }
    }

    func saveNow() {
        saveTask?.cancel()
        let snapshot = conversations
        let url = fileURL
        Task.detached(priority: .utility) { await Self.write(snapshot, to: url) }
    }

    private static func write(_ conversations: [Conversation], to url: URL) async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(conversations) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
