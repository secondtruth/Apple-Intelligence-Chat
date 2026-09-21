//
//  VoiceCatalog.swift
//  Apple Intelligence Chat
//

import AVFoundation
import NaturalLanguage

/// Knows the installed voices: which language a reply is in, and which voice
/// installed for that language is the best one.
enum VoiceCatalog {
    static func best(forLanguage language: String) -> AVSpeechSynthesisVoice? {
        ranked(forLanguage: language).first
    }

    /// Voices worth offering: the user's languages plus English, best first,
    /// without the novelty voices.
    static var selectable: [(language: String, voices: [AVSpeechSynthesisVoice])] {
        offeredLanguages.compactMap { language in
            let voices = ranked(forLanguage: language)
            return voices.isEmpty ? nil : (language, voices)
        }
    }

    /// The system's language. Not `Locale.current`: that follows the app's
    /// localizations, and an English-only app reports English on a German Mac.
    static var systemLanguage: String {
        Locale.preferredLanguages.first
            .flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en"
    }

    static var offeredLanguages: [String] {
        var seen: [String] = []
        for identifier in Locale.preferredLanguages + ["en"] {
            guard let code = Locale(identifier: identifier).language.languageCode?.identifier,
                  !seen.contains(code) else { continue }
            seen.append(code)
        }
        return seen
    }

    static func displayName(of voice: AVSpeechSynthesisVoice) -> String {
        let region = Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language
        switch voice.quality {
        case .premium: return "\(voice.name) — \(region), \(String(localized: "Premium"))"
        case .enhanced: return "\(voice.name) — \(region), \(String(localized: "Enhanced"))"
        default: return "\(voice.name) — \(region)"
        }
    }

    static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    // MARK: - Ranking

    private static func ranked(forLanguage language: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { languageCode(of: $0) == language && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { score($0) > score($1) }
    }

    /// Quality decides; below it, the families that sound synthetic lose and
    /// the user's own region wins.
    private static func score(_ voice: AVSpeechSynthesisVoice) -> Int {
        var score = voice.quality.rawValue * 100
        let identifier = voice.identifier
        if identifier.contains(".eloquence.") { score -= 50 }
        if identifier.contains(".speech.synthesis.") { score -= 40 }
        if identifier.contains(".super-compact.") { score -= 20 }
        if voice.language == AVSpeechSynthesisVoice(language: languageCode(of: voice))?.language { score += 10 }
        if let region = Locale.current.region?.identifier, voice.language.hasSuffix("-\(region)") { score += 5 }
        return score
    }

    static func languageCode(of voice: AVSpeechSynthesisVoice) -> String {
        Locale(identifier: voice.language).language.languageCode?.identifier ?? voice.language
    }

    static func language(of text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(1000)))
        return recognizer.dominantLanguage?.rawValue ?? systemLanguage
    }
}
