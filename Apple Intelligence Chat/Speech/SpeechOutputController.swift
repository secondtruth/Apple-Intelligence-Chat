//
//  SpeechOutputController.swift
//  Apple Intelligence Chat
//

import AVFoundation
import Observation

/// Reads replies aloud. One controller serves the whole app, so a second
/// reply — or the preview in Settings — replaces what is being spoken instead
/// of talking over it.
@MainActor
@Observable
final class SpeechOutputController {
    private(set) var speakingMessageID: ChatMessage.ID?
    private(set) var isPreviewing = false
    /// Why reading a reply stayed silent; the chat shows it once and clears it.
    var errorMessage: String?
    /// The same for a sample played from Settings, shown in the pane itself.
    private(set) var previewError: String?

    private let settings: SpeechSettings
    private var engine: SpeechEngine?
    private var task: Task<Void, Never>?

    init(settings: SpeechSettings) {
        self.settings = settings
    }

    func toggleSpeaking(for message: ChatMessage) {
        if speakingMessageID == message.id {
            stopSpeaking()
            return
        }
        // Read the reply, not its markup: no asterisks, no backticks, no code.
        let text = MarkdownDocument(message.text).spokenText
        guard !text.isEmpty else { return }
        start(text) { $0.speakingMessageID = message.id }
    }

    /// Plays a sentence with the current choice, so a voice can be heard
    /// before a reply is read with it.
    func togglePreview(using choice: SpeechSettings.VoiceChoice? = nil) {
        if isPreviewing {
            stopSpeaking()
            return
        }
        previewError = nil
        start(Self.sample(for: previewLanguage), choice: choice) { $0.isPreviewing = true }
    }

    /// A pane that goes away takes its error with it.
    func dismissPreviewError() {
        previewError = nil
    }

    func stopSpeaking() {
        task?.cancel()
        engine?.stop()
        engine = nil
        speakingMessageID = nil
        isPreviewing = false
    }

    private func start(_ text: String, choice: SpeechSettings.VoiceChoice? = nil,
                       mark: (SpeechOutputController) -> Void) {
        stopSpeaking()
        mark(self)
        let isPreview = isPreviewing
        task = Task {
            do {
                let engine = try makeEngine(for: text, choice: choice ?? settings.choice)
                self.engine = engine
                try await engine.speak(text)
            } catch is CancellationError {
            } catch {
                if isPreview {
                    previewError = error.localizedDescription
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            guard !Task.isCancelled else { return }
            engine = nil
            speakingMessageID = nil
            isPreviewing = false
        }
    }

    // MARK: - Choosing the engine

    private func makeEngine(for text: String, choice: SpeechSettings.VoiceChoice) throws -> SpeechEngine {
        let language = VoiceCatalog.language(of: text)
        switch choice {
        case .server:
            guard settings.serverIsConfigured else {
                throw ProviderError.notConfigured(
                    String(localized: "The speech server needs an address, a model and a voice. Set them in Settings › Speech Server."))
            }
            return ServerSpeechEngine(configuration: settings.server, voice: settings.serverVoice)
        case .systemVoice:
            return Self.systemEngine()
        case .installed(let identifier):
            // A German voice reading an English reply helps nobody.
            if let voice = AVSpeechSynthesisVoice(identifier: identifier),
               VoiceCatalog.languageCode(of: voice) == language {
                return InstalledVoiceEngine(voice: voice)
            }
            return Self.automaticEngine(for: language)
        case .automatic:
            return Self.automaticEngine(for: language)
        }
    }

    private static func automaticEngine(for language: String) -> SpeechEngine {
#if os(macOS)
        if language == SystemVoiceEngine.language { return SystemVoiceEngine() }
#endif
        return InstalledVoiceEngine(voice: VoiceCatalog.best(forLanguage: language))
    }

    private static func systemEngine() -> SpeechEngine {
#if os(macOS)
        SystemVoiceEngine()
#else
        InstalledVoiceEngine(voice: nil)
#endif
    }

    // MARK: - Preview

    private var previewLanguage: String {
        if case .installed(let identifier) = settings.choice,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return VoiceCatalog.languageCode(of: voice)
        }
        return VoiceCatalog.systemLanguage
    }

    private static func sample(for language: String) -> String {
        language == "de" ? "So klingen vorgelesene Antworten." : "This is how replies will sound."
    }
}
