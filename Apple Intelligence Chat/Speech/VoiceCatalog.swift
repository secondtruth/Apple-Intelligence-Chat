//
//  VoiceCatalog.swift
//  Apple Intelligence Chat
//

import AVFoundation
import NaturalLanguage

/// Chooses the voice a reply is read with. The system's default voice is the
/// compact one of the system language, whatever the reply is written in; this
/// looks at the reply's language and takes the best voice installed for it.
enum VoiceCatalog {
    /// Defaults key holding the chosen voice's identifier; empty means automatic.
    static let preferenceKey = "speechVoiceIdentifier"

    /// The chosen voice when it speaks the text's language, otherwise the best
    /// installed one — a German voice reading English helps nobody.
    static func voice(for text: String) -> AVSpeechSynthesisVoice? {
        let language = language(of: text)
        let chosen = UserDefaults.standard.string(forKey: preferenceKey) ?? ""
        if !chosen.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: chosen),
           languageCode(of: voice) == language {
            return voice
        }
        return best(forLanguage: language)
    }

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

    private static func languageCode(of voice: AVSpeechSynthesisVoice) -> String {
        Locale(identifier: voice.language).language.languageCode?.identifier ?? voice.language
    }

    private static func language(of text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(1000)))
        return recognizer.dominantLanguage?.rawValue
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"
    }
}
