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
            Button("Rename…", systemImage: "pencil") {
                draftTitle = conversation.title
                renamingID = conversation.id
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                store.delete(conversation.id)
            }
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) {
                store.delete(conversation.id)
            }
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renamingID != nil },
            set: { if !$0 { renamingID = nil } })
    }
}
