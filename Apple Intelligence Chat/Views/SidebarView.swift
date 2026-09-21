//
//  SidebarView.swift
//  Apple Intelligence Chat
//

import SwiftUI

/// Lists conversations newest first, grouped by day.
struct SidebarView: View {
    @Environment(ConversationStore.self) private var store

    @State private var renamingID: Conversation.ID?
    @State private var draftTitle = ""
    @State private var deletionCandidate: Conversation?

    var body: some View {
        @Bindable var store = store

        List(selection: $store.selectedID) {
            ForEach(store.grouped, id: \.group.id) { section in
                Section(section.group.title) {
                    ForEach(section.conversations) { conversation in
                        row(for: conversation)
                            .tag(conversation.id)
                    }
                }
            }
        }
        .searchable(text: $store.searchText, placement: .sidebar, prompt: Text("Search conversations"))
        .overlay {
            if store.conversations.isEmpty {
                ContentUnavailableView("No Conversations", systemImage: "bubble.left.and.bubble.right")
            } else if store.filtered.isEmpty {
                ContentUnavailableView.search(text: store.searchText)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    store.newConversation()
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .help("New chat (⌘N)")
            }
        }
        .focusedSceneValue(\.conversationActions, store.selected.map(actions))
        .confirmationDialog(
            "Delete “\(deletionCandidate?.displayTitle ?? "")”?",
            isPresented: deletionBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deletionCandidate { store.delete(deletionCandidate.id) }
                deletionCandidate = nil
            }
            Button("Cancel", role: .cancel) { deletionCandidate = nil }
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Rename Conversation", isPresented: renameBinding) {
            TextField("Title", text: $draftTitle)
            Button("Cancel", role: .cancel) { renamingID = nil }
            Button("Rename") {
                if let renamingID { store.rename(renamingID, to: draftTitle) }
                renamingID = nil
            }
        }
    }

    private func row(for conversation: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(conversation.displayTitle)
                .lineLimit(1)
            Text(conversation.snippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .contextMenu {
            let actions = actions(for: conversation)
            Button(conversation.isPinned ? "Unpin" : "Pin",
                   systemImage: conversation.isPinned ? "pin.slash" : "pin",
                   action: actions.togglePin)
            Button("Rename…", systemImage: "pencil", action: actions.rename)
            Button("Delete…", systemImage: "trash", role: .destructive, action: actions.delete)
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive, action: actions(for: conversation).delete)
        }
    }

    /// One set of actions behind the context menu, the swipe and the
    /// Conversation menu, so all three behave alike.
    private func actions(for conversation: Conversation) -> ConversationActions {
        ConversationActions(
            isPinned: conversation.isPinned,
            togglePin: { store.togglePin(conversation.id) },
            rename: {
                draftTitle = conversation.title
                renamingID = conversation.id
            },
            delete: {
                // An empty draft holds nothing worth a question.
                if conversation.isEmpty {
                    store.delete(conversation.id)
                } else {
                    deletionCandidate = conversation
                }
            })
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { deletionCandidate != nil },
            set: { if !$0 { deletionCandidate = nil } })
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renamingID != nil },
            set: { if !$0 { renamingID = nil } })
    }
}
