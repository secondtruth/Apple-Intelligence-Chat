//
//  ContentView.swift
//  Apple Intelligence Chat
//

import SwiftUI

/// Sidebar plus chat pane.
struct ContentView: View {
    @Environment(ConversationStore.self) private var store

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            if let id = store.selectedID, store.conversations.contains(where: { $0.id == id }) {
                // Keyed by conversation so per-thread view state does not leak
                // from one chat into the next.
                ChatView(conversationID: id)
                    .id(id)
            } else {
                ContentUnavailableView {
                    Label("No Conversation Selected", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Pick a conversation or start a new one.")
                } actions: {
                    Button("New Chat") { store.newConversation() }
                }
            }
        }
        .onAppear {
            if store.conversations.isEmpty { store.newConversation() }
        }
    }
}
