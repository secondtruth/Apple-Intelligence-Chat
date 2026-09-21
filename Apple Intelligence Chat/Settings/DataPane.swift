//
//  DataPane.swift
//  Apple Intelligence Chat
//

import SwiftUI

struct ConversationsPane: View {
    @Environment(ConversationStore.self) private var store
    @State private var confirmDeleteAll = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Stored on This Mac") {
                    Text("^[\(store.conversations.count) conversation](inflect: true)")
                }
                Button("Delete All Conversations…", role: .destructive) { confirmDeleteAll = true }
                    .disabled(store.conversations.isEmpty)
            }
        }
        .confirmationDialog("Delete all conversations?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) {
                store.deleteAll()
                store.saveNow()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
}
