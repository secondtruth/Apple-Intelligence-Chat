//
//  ChatView.swift
//  Apple Intelligence Chat
//

import SwiftUI

/// One conversation: the thread, the composer and the provider's status.
struct ChatView: View {
    let conversationID: Conversation.ID

    @Environment(ConversationStore.self) private var store
    @Environment(ProviderRegistry.self) private var registry
    @Environment(ChatEngine.self) private var engine

    @State private var input = ""
    @State private var inputSelection: TextSelection?
    @State private var composerHeight: CGFloat = 120
    @State private var voice = VoiceInputController()
    @State private var speech = SpeechOutputController()
    @State private var voiceError: String?
    @FocusState private var isInputFocused: Bool

    private var conversation: Conversation? {
        store.conversations.first { $0.id == conversationID }
    }

    private var messages: [ChatMessage] { conversation?.messages ?? [] }
    private var isResponding: Bool { engine.isResponding(in: conversationID) }

    var body: some View {
        // The composer floats over the thread. Its measured height reserves
        // the room scrolling and the empty state need below them. A safe-area
        // inset would do the same, but it makes the system light the region
        // around the composer separately and brighten the content on hover.
        ZStack(alignment: .bottom) {
            thread
            composerArea
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerHeight = $0 }
        }
        .navigationTitle(conversation?.displayTitle ?? String(localized: "Chat"))
        .toolbar { toolbarContent }
        .onAppear { isInputFocused = true }
        .onDisappear {
            voice.stopRecording()
            speech.stopSpeaking()
        }
        .alert("Voice Input", isPresented: .constant(voiceError != nil)) {
            Button("OK") { voiceError = nil }
        } message: {
            Text(voiceError ?? "")
        }
    }

    // MARK: - Thread

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(messages) { message in
                        MessageView(
                            message: message,
                            isStreaming: isResponding && message.id == messages.last?.id,
                            isSpeaking: speech.speakingMessageID == message.id,
                            onSpeak: message.role == .assistant
                                ? { speech.toggleSpeaking(for: message) }
                                : nil,
                            onRetry: message.role == .assistant && !isResponding
                                ? { engine.regenerate(in: conversationID) }
                                : nil)
                        .id(message.id)
                    }
                    // The scroll target: the end of the thread sits above
                    // the composer, not underneath it.
                    Color.clear
                        .frame(height: composerHeight)
                        .id(Self.threadEndID)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            // A reopened conversation shows its latest exchange, not its first.
            .defaultScrollAnchor(.bottom)
            .onChange(of: messages.count) { scrollToEnd(proxy) }
            .onChange(of: messages.last?.text) { scrollToEnd(proxy) }
            .overlay {
                if messages.isEmpty {
                    EmptyConversationView(onPick: prefill)
                        .padding(.top, 12)
                        .padding(.bottom, composerHeight)
                }
            }
        }
    }

    private static let threadEndID = "thread-end"

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard !messages.isEmpty else { return }
        withAnimation { proxy.scrollTo(Self.threadEndID, anchor: .bottom) }
    }

    // MARK: - Composer

    private var composerArea: some View {
        VStack(spacing: 8) {
            composer
            if let status = registry.statusMessage {
                statusLine(status)
            }
        }
        .padding(20)
        .frame(maxWidth: 860)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            TextField("Ask anything", text: $input, selection: $inputSelection, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .frame(minHeight: 22)
                .focused($isInputFocused)
                .disabled(isResponding)
                .onSubmit { send(input) }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            HStack(spacing: 8) {
                ModelPicker()
                Spacer(minLength: 8)

                Button(action: toggleVoiceInput) {
                    Image(systemName: voice.isRecording ? "waveform" : "mic.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(voice.isRecording ? Color.red : Color.secondary.opacity(0.75))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isResponding)
                .help(voice.isRecording ? "Stop dictation" : "Dictate a prompt")
                .accessibilityLabel(voice.isRecording ? "Stop voice input" : "Start voice input")

                Button(action: { isResponding ? engine.stop() : send(input) }) {
                    Image(systemName: isResponding ? "stop.fill" : "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(sendIsDisabled ? Color.gray.opacity(0.4) : Color.accentColor)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(sendIsDisabled)
                .help(isResponding ? "Stop generating" : "Send")
                .accessibilityLabel(isResponding ? "Stop generating" : "Send")
                .animation(.easeInOut(duration: 0.2), value: isResponding)
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.bottom, 10)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var sendIsDisabled: Bool {
        if isResponding { return false }
        if !registry.availability.isAvailable { return true }
        return input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The provider's own words about why it cannot answer — the composer stays
    /// visible above it, so the reason reads as a state, not as an error dialog.
    private func statusLine(_ status: String) -> some View {
        HStack(spacing: 6) {
            if case .checking = registry.availability {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "exclamationmark.circle")
            }
            Text(status)
#if os(macOS)
            SettingsLink { Text("Settings") }
                .buttonStyle(.link)
#endif
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
#if os(macOS)
        ToolbarItem {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
        }
#endif
    }

    // MARK: - Actions

    private func send(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isResponding, registry.availability.isAvailable else { return }
        voice.stopRecording()
        input = ""
        engine.send(prompt, in: conversationID)
        isInputFocused = true
    }

    /// Puts a starter into the composer with the caret behind it, ready for
    /// the text it refers to.
    private func prefill(_ stem: String) {
        input = stem
        isInputFocused = true
        inputSelection = TextSelection(insertionPoint: stem.endIndex)
    }

    private func toggleVoiceInput() {
        Task {
            do {
                try await voice.toggleRecording { transcript in
                    input = transcript
                }
            } catch {
                voiceError = error.localizedDescription
            }
        }
    }
}
