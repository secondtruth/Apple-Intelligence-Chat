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
    @State private var library: PromptLibrary
    @State private var runner: TextActionRunner

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = ConversationStore()
        let registry = ProviderRegistry()
        let library = PromptLibrary()
        _store = State(initialValue: store)
        _registry = State(initialValue: registry)
        _engine = State(initialValue: ChatEngine(store: store, registry: registry))
        _library = State(initialValue: library)
        _runner = State(initialValue: TextActionRunner(registry: registry, library: library))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(registry)
                .environment(engine)
                .environment(library)
                .task { installTextServices() }
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
        MenuBarExtra("Local Model", systemImage: "sparkles") {
            MenuBarContent(runner: runner)
                .environment(registry)
        }

        Settings {
            SettingsView()
                .environment(registry)
                .environment(store)
                .environment(library)
        }
#endif
    }

    /// Registers the Services menu entries. Guarded inside ServicesHost, so
    /// opening a second window does not register twice.
    private func installTextServices() {
#if os(macOS)
        ServicesHost.install(TextServicesProvider(runner: runner) { selection in
            let id = store.newConversation()
            engine.send(selection, in: id)
        })
#endif
    }
}
