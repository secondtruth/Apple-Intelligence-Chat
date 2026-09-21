//
//  Apple_Intelligence_ChatApp.swift
//  Apple Intelligence Chat
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct Apple_Intelligence_ChatApp: App {
    @State private var store: ConversationStore
    @State private var registry: ProviderRegistry
    @State private var engine: ChatEngine
    @State private var library: PromptLibrary
    @State private var runner: TextActionRunner

    @Environment(\.scenePhase) private var scenePhase

    static let mainWindowID = "main"

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
        // The explicit id keeps the frame autosave key stable. Without one the
        // key is derived from the root view's type, so every added modifier
        // made the app forget the size its window was resized to.
        WindowGroup(id: Self.mainWindowID) {
            ContentView()
                .environment(store)
                .environment(registry)
                .environment(engine)
                .environment(library)
                .task {
                    installTextServices()
                    installQuickAsk()
                }
        }
#if os(macOS)
        // Sidebar plus a text column of about 90 characters, and short enough
        // for a 13-inch display.
        .defaultSize(width: 960, height: 700)
        .windowResizability(.contentMinSize)
#endif
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

    /// Wires the quick-ask panel to the global shortcut. The shortcut is opt-in
    /// because it takes a key combination away from every other app.
    private func installQuickAsk() {
#if os(macOS)
        QuickAskController.shared.configure(runner: runner, registry: registry) { question in
            let id = store.newConversation()
            engine.send(question, in: id)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
        if UserDefaults.standard.object(forKey: "quickAskHotkeyEnabled") as? Bool ?? true {
            GlobalHotkey.shared.register { QuickAskController.shared.toggle() }
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
