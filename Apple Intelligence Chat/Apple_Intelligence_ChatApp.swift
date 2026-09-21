//
//  Apple_Intelligence_ChatApp.swift
//  Apple Intelligence Chat
//

import SwiftUI

@main
struct Apple_Intelligence_ChatApp: App {
    @State private var store: ConversationStore
    @State private var registry: ProviderRegistry
    @State private var engine: ChatEngine

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = ConversationStore()
        let registry = ProviderRegistry()
        _store = State(initialValue: store)
        _registry = State(initialValue: registry)
        _engine = State(initialValue: ChatEngine(store: store, registry: registry))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(registry)
                .environment(engine)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") { store.newConversation() }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // The debounced writer may still be waiting when the app leaves
            // the foreground.
            if phase != .active { store.saveNow() }
        }

#if os(macOS)
        Settings {
            SettingsView()
                .environment(registry)
                .environment(store)
        }
#endif
    }
}
