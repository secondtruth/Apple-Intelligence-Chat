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
        ZStack(alignment: .bottom) {
            thread
            composerArea
        }
        .navigationTitle(conversation?.displayTitle ?? String(localized: "Chat"))
#if os(macOS)
        .navigationSubtitle(providerLabel)
#endif
        .toolbar { toolbarContent }
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
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 140) // room for the floating composer
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: messages.count) { scrollToEnd(proxy) }
            .onChange(of: messages.last?.text) { scrollToEnd(proxy) }
            .overlay {
                if messages.isEmpty { emptyState }
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: registry.kind.symbolName)
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Ask anything")
                .font(.title2.weight(.semibold))
            Text(providerLabel)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(Self.starters, id: \.self) { starter in
                    Button(starter) { send(starter) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.top, 4)
        }
        .padding(.bottom, 80)
        .allowsHitTesting(registry.availability.isAvailable)
        .opacity(registry.availability.isAvailable ? 1 : 0.5)
    }

    private static let starters = [
        String(localized: "Explain this error"),
        String(localized: "Summarize a text"),
        String(localized: "Draft a reply"),
    ]

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
        ZStack {
            TextField("Ask anything", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .frame(minHeight: 22)
                .focused($isInputFocused)
                .disabled(isResponding)
                .onSubmit { send(input) }
                .padding(.vertical, 16)
                .padding(.leading, 16)
                .padding(.trailing, 96)

            HStack(spacing: 8) {
                Spacer()
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
                .animation(.easeInOut(duration: 0.2), value: isResponding)
                .padding(.trailing, 10)
            }
        }
        .glassEffect(.regular.interactive())
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
        ToolbarItem {
            Menu {
                Picker("Provider", selection: providerBinding) {
                    ForEach(ProviderKind.allCases) { kind in
                        Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
                    }
                }
                .pickerStyle(.inline)

                if registry.kind == .openAICompatible, !registry.models.isEmpty {
                    Picker("Model", selection: modelBinding) {
                        ForEach(registry.models, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }

                Divider()
                Button("Check Again", systemImage: "arrow.clockwise") { registry.refresh() }
            } label: {
                Label(providerLabel, systemImage: registry.kind.symbolName)
            }
            .help("Choose where answers come from")
        }

#if os(macOS)
        ToolbarItem {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
        }
#endif
    }

    private var providerLabel: String {
        switch registry.kind {
        case .appleIntelligence:
            return ProviderKind.appleIntelligence.displayName
        case .openAICompatible:
            let model = registry.openAIConfiguration.model
            return model.isEmpty ? ProviderKind.openAICompatible.displayName : model
        }
    }

    private var providerBinding: Binding<ProviderKind> {
        Binding(get: { registry.kind }, set: { registry.kind = $0 })
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { registry.openAIConfiguration.model },
            set: { registry.openAIConfiguration.model = $0 })
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
