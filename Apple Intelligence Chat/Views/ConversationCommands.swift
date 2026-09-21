//
//  ConversationCommands.swift
//  Apple Intelligence Chat
//

import SwiftUI

/// What can be done to the selected conversation. The sidebar publishes it;
/// the menu bar reads it, so both run the same code.
struct ConversationActions {
    let isPinned: Bool
    let togglePin: () -> Void
    let rename: () -> Void
    let delete: () -> Void
}

extension FocusedValues {
    @Entry var conversationActions: ConversationActions?
}

/// The Conversation menu, for the actions that otherwise hide in the sidebar's
/// context menu.
struct ConversationCommands: Commands {
    @FocusedValue(\.conversationActions) private var actions

    var body: some Commands {
        CommandMenu("Conversation") {
            Group {
                Button(actions?.isPinned == true ? "Unpin Conversation" : "Pin Conversation") {
                    actions?.togglePin()
                }
                Button("Rename…") { actions?.rename() }
                Divider()
                Button("Delete Conversation…") { actions?.delete() }
            }
            .disabled(actions == nil)
        }
    }
}
