//
//  SpeechEngine.swift
//  Apple Intelligence Chat
//

import AVFoundation
#if os(macOS)
import AppKit
#endif

/// One way of turning text into sound. `speak` returns when the text has been
/// spoken or `stop` was called, and throws when it could not be spoken.
@MainActor
protocol SpeechEngine: AnyObject {
    func speak(_ text: String) async throws
    func stop()
}

/// A voice installed on this device, through AVSpeechSynthesizer.
@MainActor
final class InstalledVoiceEngine: NSObject, SpeechEngine, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    private var continuation: CheckedContinuation<Void, Never>?

    init(voice: AVSpeechSynthesisVoice?) {
        self.voice = voice
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) async throws {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        finish()
    }

    private func finish() {
        continuation?.resume()
        continuation = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }
}

#if os(macOS)
/// The voice chosen in System Settings › Accessibility › Spoken Content.
///
/// A Siri voice selected there is neither listed to a sandboxed app nor
/// addressable by identifier, and AVSpeechSynthesizer without a voice falls
/// back to the compact one. NSSpeechSynthesizer without a voice does speak
/// with it — measured: the same sentence takes 4.5 s here and 6.2 s with the
/// compact voice — which is why this deprecated class is still in use.
@MainActor
final class SystemVoiceEngine: NSObject, SpeechEngine, NSSpeechSynthesizerDelegate {
    private let synthesizer = NSSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) async throws {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            if !synthesizer.startSpeaking(text) { finish() }
        }
    }

    func stop() {
        synthesizer.stopSpeaking()
        finish()
    }

    private func finish() {
        continuation?.resume()
        continuation = nil
    }

    nonisolated func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        Task { @MainActor in self.finish() }
    }

    /// Language of the system voice. An empty default voice is the hidden
    /// Siri voice, which follows the system language.
    static var language: String {
        let voice = NSSpeechSynthesizer.defaultVoice
        if !voice.rawValue.isEmpty,
           let locale = NSSpeechSynthesizer.attributes(forVoice: voice)[.localeIdentifier] as? String,
           let code = Locale(identifier: locale).language.languageCode?.identifier {
            return code
        }
        return VoiceCatalog.systemLanguage
    }
}
#endif
