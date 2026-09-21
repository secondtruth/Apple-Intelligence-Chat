//
//  SpeechPanes.swift
//  Apple Intelligence Chat
//

import AVFoundation
import SwiftUI

struct ReadAloudPane: View {
    @Environment(SpeechSettings.self) private var settings
    @Environment(SpeechOutputController.self) private var speech
    @AppStorage(SettingsPane.selectionKey) private var pane: SettingsPane = .readAloud

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                // The label has two lines; the button follows the first, like
                // the picker's control does.
                HStack(alignment: .firstTextBaseline) {
                    Picker(selection: $settings.choice) {
                        Text("Automatic").tag(SpeechSettings.VoiceChoice.automatic)
#if os(macOS)
                        Text("System Voice").tag(SpeechSettings.VoiceChoice.systemVoice)
#endif
                        Text("Speech Server").tag(SpeechSettings.VoiceChoice.server)
                        ForEach(VoiceCatalog.selectable, id: \.language) { group in
                            Section(VoiceCatalog.languageName(group.language)) {
                                ForEach(group.voices, id: \.identifier) { voice in
                                    Text(VoiceCatalog.displayName(of: voice))
                                        .tag(SpeechSettings.VoiceChoice.installed(identifier: voice.identifier))
                                }
                            }
                        }
                    } label: {
                        SettingLabel("Voice", detail: automaticResolution)
                    }
                    PreviewButton(choice: nil)
                }

                if settings.choice == .server, !settings.serverIsConfigured {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("The speech server is not set up yet.")
                        Spacer()
                        Button("Set Up…") { pane = .speechServer }
                    }
                }
                PreviewErrorRow()
            } footer: {
                Text("The System Voice is the one chosen in System Settings › Accessibility › Spoken Content, where more natural voices can also be downloaded; a Siri voice chosen there works here although it is not listed. An installed voice is used for replies in its own language.")
            }
        }
        .onDisappear {
            speech.stopSpeaking()
            speech.dismissPreviewError()
        }
    }

    /// Names what Automatic means on this Mac instead of leaving it to be
    /// found out by listening.
    private var automaticResolution: String {
        let resolved = VoiceCatalog.offeredLanguages.compactMap { language -> String? in
#if os(macOS)
            if language == SystemVoiceEngine.language {
                return "\(VoiceCatalog.languageName(language)): \(String(localized: "System Voice"))"
            }
#endif
            guard let voice = VoiceCatalog.best(forLanguage: language) else { return nil }
            return "\(VoiceCatalog.languageName(language)): \(voice.name)"
        }
        return String(localized: "Automatic reads a reply in its own language: \(resolved.joined(separator: ", ")).")
    }
}

struct SpeechServerPane: View {
    @Environment(SpeechSettings.self) private var settings
    @Environment(SpeechOutputController.self) private var speech

    @State private var voices: [String] = []

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                TextField("Base URL", text: $settings.server.baseURL, prompt: Text("http://localhost:8880/v1"))
                    .textContentType(.URL)
#if os(iOS)
                    .autocapitalization(.none)
                    .keyboardType(.URL)
#endif
                SecureField("API Key", text: $settings.server.apiKey, prompt: Text("Optional"))
                TextField("Model", text: $settings.server.model, prompt: Text("kokoro, tts-1 …"))

                if voices.isEmpty {
                    TextField("Voice", text: $settings.serverVoice, prompt: Text("af_heart, alloy …"))
                } else {
                    Picker("Voice", selection: $settings.serverVoice) {
                        if !voices.contains(settings.serverVoice) {
                            Text(settings.serverVoice.isEmpty ? String(localized: "Choose…") : settings.serverVoice)
                                .tag(settings.serverVoice)
                        }
                        ForEach(voices, id: \.self) { Text($0).tag($0) }
                    }
                }
            } footer: {
                Text("Any server with OpenAI's speech endpoint, `/audio/speech`: OpenAI itself, or one you run, such as Kokoro-FastAPI, Speaches or LocalAI. Chat servers like Ollama do not synthesize speech, so this is an address of its own. Replies are sent there as text when Read Aloud uses the speech server.")
            }

            Section {
                HStack {
                    Text("Test")
                    Spacer()
                    PreviewButton(choice: .server)
                        .disabled(!settings.serverIsConfigured)
                }
                PreviewErrorRow()
            }
        }
        .task(id: settings.server) {
            // Typing an address should not open a connection per keystroke.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            voices = await ServerSpeechEngine.voices(of: settings.server)
        }
        .onDisappear {
            speech.stopSpeaking()
            speech.dismissPreviewError()
        }
    }
}

/// Plays a sample with the chosen voice, or with `choice` when a pane tests
/// something other than the current selection.
private struct PreviewButton: View {
    let choice: SpeechSettings.VoiceChoice?

    @Environment(SpeechOutputController.self) private var speech

    var body: some View {
        Button(speech.isPreviewing ? "Stop" : "Play Sample",
               systemImage: speech.isPreviewing ? "stop.fill" : "play.fill") {
            speech.togglePreview(using: choice)
        }
        .labelStyle(.iconOnly)
        .help(speech.isPreviewing ? "Stop" : "Play a sample")
    }
}

private struct PreviewErrorRow: View {
    @Environment(SpeechOutputController.self) private var speech

    var body: some View {
        if let error = speech.previewError {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).textSelection(.enabled)
            }
        }
    }
}
