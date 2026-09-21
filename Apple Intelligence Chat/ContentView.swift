//
//  ContentView.swift
//  Apple Intelligence Chat
//
//  Created by Pallav Agarwal on 6/9/25.
//

import SwiftUI
import FoundationModels

/// Main chat interface view
struct ContentView: View {
    // MARK: - State Properties
    
    // UI State
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isResponding = false
    @State private var showSettings = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var voiceInputController = VoiceInputController()
    @State private var speechOutputController = SpeechOutputController()
    
    // Model State
    @State private var session: LanguageModelSession?
    @State private var streamingTask: Task<Void, Never>?
    @State private var model = SystemLanguageModel.default
    
    // Settings
    @AppStorage("useStreaming") private var useStreaming = AppSettings.useStreaming
    @AppStorage("temperature") private var temperature = AppSettings.temperature
    @AppStorage("systemInstructions") private var systemInstructions = AppSettings.systemInstructions
    
    // Haptics
#if os(iOS)
    private let hapticStreamGenerator = UISelectionFeedbackGenerator()
#endif
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Chat Messages ScrollView
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack {
                            ForEach(messages) { message in
                                MessageView(
                                    message: message,
                                    isResponding: isResponding,
                                    isSpeaking: speechOutputController.speakingMessageID == message.id,
                                    onSpeak: message.role == .assistant ? {
                                        speechOutputController.toggleSpeaking(for: message)
                                    } : nil
                                )
                                    .id(message.id)
                            }
                        }
                        .padding()
                        .padding(.bottom, 90) // Space for floating input field
                    }
                    .onChange(of: messages.count) {
                        if let lastMessage = messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: messages.last?.text) {
                        if let lastMessage = messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Floating Input Field
                VStack {
                    Spacer()
                    inputField
                        .padding(20)
                }
            }
            .navigationTitle("Apple Intelligence Chat")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar { toolbarContent }
            .sheet(isPresented: $showSettings) {
                SettingsView {
                    session = nil // Reset session on settings change
                }
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .onDisappear {
                voiceInputController.stopRecording()
                speechOutputController.stopSpeaking()
                stopStreaming()
            }
        }
    }
    
    // MARK: - Subviews
    
    /// Floating input field with send/stop button
    private var inputField: some View {
        ZStack {
            TextField("Ask anything", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .frame(minHeight: 22)
                .disabled(isResponding)
                .onSubmit {
                    if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        handleSendOrStop()
                    }
                }
                .padding(.vertical, 16)
                .padding(.leading, 16)
                .padding(.trailing, 96)
            
            HStack(spacing: 8) {
                Spacer()
                Button(action: toggleVoiceInput) {
                    Image(systemName: voiceInputController.isRecording ? "waveform" : "mic.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(voiceInputController.isRecording ? Color.red : Color.secondary.opacity(0.75))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isResponding)
                .accessibilityLabel(voiceInputController.isRecording ? "Stop voice input" : "Start voice input")

                Button(action: handleSendOrStop) {
                    Image(systemName: isResponding ? "stop.fill" : "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(isSendButtonDisabled ? Color.gray.opacity(0.4) : Color.accentColor)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isSendButtonDisabled)
                .animation(.easeInOut(duration: 0.2), value: isResponding)
                .animation(.easeInOut(duration: 0.2), value: isSendButtonDisabled)
                .padding(.trailing, 10)
            }
        }
        .glassEffect(.regular.interactive())
    }
    
    private var isSendButtonDisabled: Bool {
        return inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
#if os(iOS)
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: resetConversation) {
                Label("New Chat", systemImage: "square.and.pencil")
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: { showSettings = true }) {
                Label("Settings", systemImage: "gearshape")
            }
        }
#else
        ToolbarItem {
            Button(action: resetConversation) {
                Label("New Chat", systemImage: "square.and.pencil")
            }
        }
        ToolbarItem {
            Button(action: { showSettings = true }) {
                Label("Settings", systemImage: "gearshape")
            }
        }
#endif
    }
    
    // MARK: - Model Interaction
    
    private func handleSendOrStop() {
        if isResponding {
            stopStreaming()
        } else {
            guard model.isAvailable else {
                showError(message: "The language model is not available. Reason: \(availabilityDescription(for: model.availability))")
                return
            }
            sendMessage()
        }
    }
    
    private func sendMessage() {
        voiceInputController.stopRecording()
        isResponding = true
        let userMessage = ChatMessage(role: .user, text: inputText)
        messages.append(userMessage)
        let prompt = inputText
        inputText = ""
        
        // Add empty assistant message for streaming
        messages.append(ChatMessage(role: .assistant, text: ""))
        
        streamingTask = Task {
            do {
                if session == nil { session = createSession() }
                
                guard let currentSession = session else {
                    showError(message: "Session could not be created.")
                    isResponding = false
                    return
                }
                
                let options = GenerationOptions(temperature: temperature)
                
                if useStreaming {
                    let stream = currentSession.streamResponse(to: prompt, options: options)
                    for try await partialResponse in stream {
#if os(iOS)
                        hapticStreamGenerator.selectionChanged()
#endif
                        updateLastMessage(with: partialResponse.content)
                    }
                } else {
                    let response = try await currentSession.respond(to: prompt, options: options)
                    updateLastMessage(with: response.content)
                }
            } catch is CancellationError {
                // User cancelled generation
            } catch {
                showError(message: "An error occurred: \(error.localizedDescription)")
            }
            
            isResponding = false
            streamingTask = nil
        }
    }
    
    private func stopStreaming() {
        streamingTask?.cancel()
    }

    private func toggleVoiceInput() {
        Task {
            do {
                try await voiceInputController.toggleRecording { transcript in
                    inputText = transcript
                }
            } catch {
                showError(message: error.localizedDescription)
            }
        }
    }
    
    @MainActor
    private func updateLastMessage(with text: String) {
        messages[messages.count - 1].text = text
    }
    
    // MARK: - Session & Helpers
    
    private func createSession() -> LanguageModelSession {
        return LanguageModelSession(instructions: systemInstructions)
    }
    
    private func resetConversation() {
        voiceInputController.stopRecording()
        speechOutputController.stopSpeaking()
        stopStreaming()
        messages.removeAll()
        session = nil
    }
    
    private func availabilityDescription(for availability: SystemLanguageModel.Availability) -> String {
        switch availability {
            case .available:
                return "Available"
            case .unavailable(let reason):
                switch reason {
                    case .deviceNotEligible:
                        return "Device not eligible"
                    case .appleIntelligenceNotEnabled:
                        return "Apple Intelligence not enabled in Settings"
                    case .modelNotReady:
                        return "Model assets not downloaded"
                    @unknown default:
                        return "Unknown reason"
                }
            @unknown default:
                return "Unknown availability"
        }
    }
    
    @MainActor
    private func showError(message: String) {
        self.errorMessage = message
        self.showErrorAlert = true
        self.isResponding = false
    }
}

#Preview {
    ContentView()
}
