//
//  Conversation.swift
//  Apple Intelligence Chat
//

import Foundation

/// A stored chat thread. Conversations are the unit the sidebar lists and the
/// unit a provider keeps its session state for.
struct Conversation: Identifiable, Equatable, Codable, Sendable {
    var id: UUID = UUID()
    var title: String = ""
    var messages: [ChatMessage] = []
    var createdAt: Date = .now
    var updatedAt: Date = .now

    /// Optional rather than a flag, so files written before pinning existed
    /// still decode.
    var pinnedAt: Date?

    var isEmpty: Bool { messages.isEmpty }
    var isPinned: Bool { pinnedAt != nil }

    var displayTitle: String {
        title.isEmpty ? String(localized: "New Chat") : title
    }

    /// First line of the most recent message, for the sidebar row — without
    /// the Markdown markers a reply tends to open with.
    var snippet: String {
        let placeholder = String(localized: "No messages yet")
        guard let last = messages.last(where: { !$0.text.isEmpty }) else { return placeholder }
        let firstLine = last.text
            .split(whereSeparator: \.isNewline)
            .lazy
            // A fence line holds a language name, not something said.
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#>-*+|` \t")) }
            .first { !$0.isEmpty }
        guard let firstLine else { return placeholder }
        return firstLine
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
    }

    /// Derives a title from the first user message. Called once, after the
    /// first exchange completes, so the sidebar stops saying "New Chat".
    mutating func deriveTitleIfNeeded() {
        guard title.isEmpty,
              let first = messages.first(where: { $0.role == .user && !$0.text.isEmpty })
        else { return }

        let collapsed = first.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return }

        if collapsed.count <= 48 {
            title = collapsed
        } else {
            // Cut at the last word boundary that still fits, so titles do not
            // end mid-word.
            let limit = collapsed.index(collapsed.startIndex, offsetBy: 48)
            let head = collapsed[collapsed.startIndex..<limit]
            let cut = head.lastIndex(of: " ").map { head[head.startIndex..<$0] } ?? head
            title = cut.trimmingCharacters(in: .whitespaces) + "…"
        }
    }
}

/// Sidebar sections, newest first.
enum ConversationDateGroup: Int, CaseIterable, Identifiable, Sendable {
    case pinned, today, yesterday, previousWeek, previousMonth, earlier

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .pinned: String(localized: "Pinned")
        case .today: String(localized: "Today")
        case .yesterday: String(localized: "Yesterday")
        case .previousWeek: String(localized: "Previous 7 Days")
        case .previousMonth: String(localized: "Previous 30 Days")
        case .earlier: String(localized: "Earlier")
        }
    }

    static func group(for date: Date, now: Date = .now, calendar: Calendar = .current) -> ConversationDateGroup {
        if calendar.isDateInToday(date) { return .today }
        if calendar.isDateInYesterday(date) { return .yesterday }

        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days < 7 { return .previousWeek }
        if days < 30 { return .previousMonth }
        return .earlier
    }
}
