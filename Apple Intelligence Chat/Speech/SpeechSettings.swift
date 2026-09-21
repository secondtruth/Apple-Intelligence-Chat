//
//  SpeechSettings.swift
//  Apple Intelligence Chat
//

import Foundation
import Observation

/// What reads replies aloud, and how the speech server is reached.
@MainActor
@Observable
final class SpeechSettings {
    enum VoiceChoice: Hashable, Sendable {
        /// The system voice for the system's language, the best installed
        /// voice for every other.
        case automatic
        /// The voice chosen in System Settings, whatever the reply's language.
        case systemVoice
        case installed(identifier: String)
        case server

        fileprivate var stored: String {
            switch self {
            case .automatic: ""
            case .systemVoice: "system"
            case .server: "server"
            case .installed(let identifier): identifier
            }
        }

        fileprivate init(stored: String) {
            switch stored {
            case "": self = .automatic
            case "system": self = .systemVoice
            case "server": self = .server
            default: self = .installed(identifier: stored)
            }
        }
    }

    var choice: VoiceChoice {
        didSet { Defaults.voice = choice.stored }
    }

    /// Address, key and model of the speech server. It is its own server:
    /// the usual chat servers, Ollama among them, do not synthesize speech.
    var server: OpenAICompatibleProvider.Configuration {
        didSet {
            guard server != oldValue else { return }
            Defaults.serverBaseURL = server.baseURL
            Defaults.serverModel = server.model
            KeychainStore.write(server.apiKey, account: Self.keychainAccount)
        }
    }

    var serverVoice: String {
        didSet { Defaults.serverVoice = serverVoice }
    }

    var serverIsConfigured: Bool {
        server.normalizedBaseURL != nil && !server.model.isEmpty && !serverVoice.isEmpty
    }

    private static let keychainAccount = "speech-server"

    init() {
        choice = VoiceChoice(stored: Defaults.voice)
        server = OpenAICompatibleProvider.Configuration(
            baseURL: Defaults.serverBaseURL,
            apiKey: KeychainStore.read(Self.keychainAccount),
            model: Defaults.serverModel)
        serverVoice = Defaults.serverVoice
    }

    private enum Defaults {
        @UserDefault("speechVoiceIdentifier", default: "")
        static var voice: String

        @UserDefault("speechServerBaseURL", default: "")
        static var serverBaseURL: String

        @UserDefault("speechServerModel", default: "")
        static var serverModel: String

        @UserDefault("speechServerVoice", default: "")
        static var serverVoice: String
    }
}
