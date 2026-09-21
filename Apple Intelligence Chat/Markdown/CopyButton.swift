//
//  CopyButton.swift
//  Apple Intelligence Chat
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Copies a text and confirms it for two seconds. Shared by the reply's
/// action row and by code blocks, so both confirm the same way.
struct CopyButton: View {
    let text: String
    var help: LocalizedStringKey = "Copy"

    @State private var didCopy = false

    var body: some View {
        Button {
            copy()
        } label: {
            Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
        }
        .help(help)
    }

    private func copy() {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#else
        UIPasteboard.general.string = text
#endif
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}
