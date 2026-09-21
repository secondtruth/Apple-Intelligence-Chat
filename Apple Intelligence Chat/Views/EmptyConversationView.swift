//
//  EmptyConversationView.swift
//  Apple Intelligence Chat
//

import SwiftUI

/// What a new conversation shows before its first message: who will answer
/// and where the text goes, a few prompts to begin from, and the two ways into
/// the app that do not start in this window.
struct EmptyConversationView: View {
    @Environment(ProviderRegistry.self) private var registry
    @AppStorage("quickAskHotkeyEnabled") private var quickAskHotkeyEnabled = true

    /// Receives the beginning of a prompt for the composer.
    let onPick: (String) -> Void

    var body: some View {
        // A short window drops the hints first, then the starters.
        ViewThatFits(in: .vertical) {
            content(starters: true, hints: true)
            content(starters: true, hints: false)
            content(starters: false, hints: false)
        }
        .frame(maxWidth: 380)
        .padding(.horizontal, 20)
    }

    private func content(starters: Bool, hints: Bool) -> some View {
        VStack(spacing: 20) {
            identity
            if starters { starterList }
            if hints { entryHints }
        }
    }

    // MARK: - Who answers

    private var identity: some View {
        VStack(spacing: 6) {
            Image(systemName: registry.kind.symbolName)
                .font(.system(size: 28))
                .foregroundStyle(.tint)
                .padding(.bottom, 6)
            Text(registry.choiceLabel)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(destination)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// Where a message goes is the difference between the providers that
    /// matters most, so it is said rather than implied by a product name.
    private var destination: String {
        switch registry.kind {
        case .appleIntelligence:
            String(localized: "Runs on this Mac. Nothing you type leaves it.")
        case .openAICompatible:
            if registry.serverIsLocal {
                String(localized: "Runs on this Mac, served at \(registry.serverHost).")
            } else {
                String(localized: "Your messages are sent to \(registry.serverHost).")
            }
        }
    }

    // MARK: - Starters

    private var starterList: some View {
        VStack(spacing: 0) {
            ForEach(Starter.all) { starter in
                StarterRow(starter: starter) { onPick(starter.stem) }

                if starter.id != Starter.all.last?.id {
                    Divider().padding(.leading, 40)
                }
            }
        }
        .background(.quaternary.opacity(0.5))
        // Clipped, so a row's highlight follows the rounded corners.
        .clipShape(.rect(cornerRadius: 10))
        .disabled(!registry.availability.isAvailable)
    }

    // MARK: - Other ways in

    private var entryHints: some View {
        VStack(spacing: 4) {
#if os(macOS)
            if quickAskHotkeyEnabled {
                Text("\(GlobalHotkey.displayShortcut) asks from any app.")
            }
            Text("Select text anywhere, then Services, to rewrite, summarize or translate it.")
#endif
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
}

/// The beginning of a prompt. A starter fills the composer instead of sending,
/// because every one of them needs material only the user has.
private struct Starter: Identifiable {
    let title: String
    let symbolName: String
    let stem: String

    var id: String { title }

    static let all = [
        Starter(
            title: String(localized: "Summarize a text"),
            symbolName: "text.line.first.and.arrowtriangle.forward",
            stem: String(localized: "Summarize this text:\n\n")),
        Starter(
            title: String(localized: "Explain an error message"),
            symbolName: "exclamationmark.bubble",
            stem: String(localized: "Explain this error and how to fix it:\n\n")),
        Starter(
            title: String(localized: "Draft a reply"),
            symbolName: "arrowshape.turn.up.left",
            stem: String(localized: "Draft a reply to this message:\n\n")),
    ]
}

/// One starter. Hover and press only tint the row under the pointer.
private struct StarterRow: View {
    let starter: Starter
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Symbols differ in width; a fixed column keeps the titles
                // on one edge.
                Image(systemName: starter.symbolName)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(starter.title)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .contentShape(.rect)
        }
        .buttonStyle(StarterRowStyle(isHovering: isHovering))
        .onHover { isHovering = $0 }
    }
}

private struct StarterRowStyle: ButtonStyle {
    let isHovering: Bool

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? .primary : .tertiary)
            .background(.primary.opacity(fill(pressed: configuration.isPressed)))
    }

    private func fill(pressed: Bool) -> Double {
        guard isEnabled else { return 0 }
        if pressed { return 0.12 }
        return isHovering ? 0.06 : 0
    }
}
