//
//  SettingsView.swift
//  Apple Intelligence Chat
//

import SwiftUI

/// The panes of the Settings window, in the groups its sidebar shows.
enum SettingsPane: String, CaseIterable, Identifiable {
    case chatServer, generation
    case readAloud, speechServer
    case quickAsk, textActions
    case conversations

    /// Defaults key of the selected pane. Other windows set it before opening
    /// Settings, to land on the pane they mean.
    static let selectionKey = "settingsPane"

    /// Answers, speech, what works across the system, data. Like System
    /// Settings, the sidebar separates the groups by space and leaves them
    /// unnamed.
    static let groups: [[SettingsPane]] = [
        [.chatServer, .generation],
        [.readAloud, .speechServer],
        [.quickAsk, .textActions],
        [.conversations],
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chatServer: String(localized: "Chat Server")
        case .generation: String(localized: "Generation")
        case .readAloud: String(localized: "Read Aloud")
        case .speechServer: String(localized: "Speech Server")
        case .quickAsk: String(localized: "Quick Ask")
        case .textActions: String(localized: "Text Actions")
        case .conversations: String(localized: "Conversations")
        }
    }

    var symbolName: String {
        switch self {
        case .chatServer: "server.rack"
        case .generation: "slider.horizontal.3"
        case .readAloud: "speaker.wave.2"
        case .speechServer: "waveform"
        case .quickAsk: "bolt"
        case .textActions: "text.cursor"
        case .conversations: "bubble.left.and.bubble.right.fill"
        }
    }

    var tint: Color {
        switch self {
        case .chatServer: .blue
        case .generation: .gray
        case .readAloud: .pink
        case .speechServer: .indigo
        case .quickAsk: .orange
        case .textActions: .teal
        case .conversations: .green
        }
    }
}

/// The sidebar's icon: a white glyph on a coloured tile, as in System Settings.
private struct PaneIcon: View {
    let pane: SettingsPane

    var body: some View {
        Image(systemName: pane.symbolName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(pane.tint.gradient, in: .rect(cornerRadius: 5))
    }
}

/// A control's label with its explanation underneath, inside the row — where
/// System Settings puts it — rather than in a footer below the group.
struct SettingLabel: View {
    let title: LocalizedStringKey
    let detail: String

    init(_ title: LocalizedStringKey, detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A sidebar of grouped panes laid out the way System Settings lays its own
/// out — icon tiles, unnamed groups, a window that only grows downwards. One
/// long form had grown to seven unrelated sections.
struct SettingsView: View {
    @AppStorage(SettingsPane.selectionKey) private var pane: SettingsPane = .chatServer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                ForEach(SettingsPane.groups, id: \.first) { group in
                    Section {
                        ForEach(group) { pane in
                            Label {
                                Text(pane.title)
                            } icon: {
                                PaneIcon(pane: pane)
                            }
                            .tag(pane)
                        }
                    }
                }
            }
            // The Settings scene ignores the column width alone and cuts the
            // longest title off; the minimum frame holds it.
            .frame(minWidth: 220)
            .navigationSplitViewColumnWidth(min: 220, ideal: 220, max: 220)
#if os(macOS)
            .toolbar(removing: .sidebarToggle)
#endif
        } detail: {
            content
                .formStyle(.grouped)
                .navigationTitle(pane.title)
        }
#if os(macOS)
        .frame(width: 780)
        .frame(minHeight: 440, idealHeight: 540, maxHeight: .infinity)
#else
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
#endif
    }

    @ViewBuilder
    private var content: some View {
        switch pane {
        case .chatServer: ChatServerPane()
        case .generation: GenerationPane()
        case .readAloud: ReadAloudPane()
        case .speechServer: SpeechServerPane()
        case .quickAsk: QuickAskPane()
        case .textActions: TextActionsPane()
        case .conversations: ConversationsPane()
        }
    }

    private var selection: Binding<SettingsPane?> {
        Binding(get: { pane }, set: { if let value = $0 { pane = value } })
    }
}
