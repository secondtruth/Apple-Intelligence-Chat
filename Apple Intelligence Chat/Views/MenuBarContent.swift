//
//  MenuBarContent.swift
//  Apple Intelligence Chat
//

#if os(macOS)
import AppKit
import SwiftUI

/// The menu-bar item. The Services menu works on a selection; this works on
/// the clipboard, which is the only text a menu has access to.
struct MenuBarContent: View {
    @Environment(ProviderRegistry.self) private var registry
    let runner: TextActionRunner

    @State private var lastResult: String?
    @State private var lastError: String?
    @State private var isRunning = false

    var body: some View {
        Button("Quick Ask") { QuickAskController.shared.show() }
        Button("Open Chat") { activate() }

        Divider()

        ForEach(TextActionRole.allCases) { role in
            Button("\(role.title) Clipboard") { apply(role) }
                .disabled(isRunning || !registry.availability.isAvailable)
        }

        if isRunning {
            Text("Working…")
        } else if let lastResult {
            Text(lastResult)
        } else if let lastError {
            Text(lastError)
        }

        Divider()

        Text(statusText)
        Button("Settings…") {
            activate()
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusText: String {
        switch registry.availability {
        case .checking: String(localized: "Checking…")
        case .available: registry.kind.displayName
        case .unavailable(let reason, _): reason
        }
    }

    private func activate() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }

    /// Replaces the clipboard with the transformed text, so the next paste is
    /// the result — the same gesture the Services entries perform in place.
    private func apply(_ role: TextActionRole) {
        guard let selection = NSPasteboard.general.string(forType: .string) else {
            lastError = String(localized: "The clipboard holds no text.")
            return
        }

        isRunning = true
        lastResult = nil
        lastError = nil

        Task {
            do {
                let text = try await runner.run(role, on: selection)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                lastResult = String(localized: "Result copied — ⌘V to paste")
            } catch {
                lastError = error.localizedDescription
            }
            isRunning = false
        }
    }
}
#endif
