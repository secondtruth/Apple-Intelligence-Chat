//
//  ServerSpeechEngine.swift
//  Apple Intelligence Chat
//

import AVFoundation

/// Speech from a server that implements OpenAI's `/audio/speech` — OpenAI
/// itself, or a local one such as Kokoro-FastAPI, Speaches or LocalAI.
@MainActor
final class ServerSpeechEngine: NSObject, SpeechEngine, AVAudioPlayerDelegate {
    private let configuration: OpenAICompatibleProvider.Configuration
    private let voice: String
    private let session: URLSession

    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Never>?
    private var isStopped = false

    init(configuration: OpenAICompatibleProvider.Configuration, voice: String) {
        self.configuration = configuration
        self.voice = voice
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        session = URLSession(configuration: config)
    }

    func speak(_ text: String) async throws {
        isStopped = false
        // The API caps one request at 4096 characters, and a short first
        // piece starts playing sooner. The next piece loads while one plays.
        let pieces = Self.pieces(of: text, limit: 1200)
        guard !pieces.isEmpty else { return }

        var pending = Task { try await self.audio(for: pieces[0]) }
        for index in pieces.indices {
            let data = try await pending.value
            if index + 1 < pieces.count {
                let next = pieces[index + 1]
                pending = Task { try await self.audio(for: next) }
            }
            guard !isStopped else { pending.cancel(); return }
            try await play(data)
            guard !isStopped else { pending.cancel(); return }
        }
    }

    func stop() {
        isStopped = true
        player?.stop()
        finish()
    }

    // MARK: - Request

    private func audio(for text: String) async throws -> Data {
        guard let url = configuration.endpoint("audio/speech") else {
            throw ProviderError.notConfigured(String(localized: "The speech server address is not a valid URL."))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !configuration.apiKey.isEmpty {
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(SpeechRequest(
            model: configuration.model, input: text, voice: voice, responseFormat: "mp3"))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ProviderError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.transport(String(localized: "The speech server sent no HTTP response."))
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw ProviderError.server(status: http.statusCode, message: message)
        }
        return data
    }

    private struct SpeechRequest: Encodable {
        let model: String
        let input: String
        let voice: String
        let responseFormat: String

        enum CodingKeys: String, CodingKey {
            case model, input, voice
            case responseFormat = "response_format"
        }
    }

    /// Voices the server offers. Not part of OpenAI's API; Kokoro-FastAPI and
    /// others answer `/audio/voices`, and a server without it leaves the
    /// voice a text field.
    static func voices(of configuration: OpenAICompatibleProvider.Configuration) async -> [String] {
        guard let url = configuration.endpoint("audio/voices") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        if !configuration.apiKey.isEmpty {
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        }
        struct Listing: Decodable { let voices: [String] }
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let listing = try? JSONDecoder().decode(Listing.self, from: data)
        else { return [] }
        return listing.voices.sorted()
    }

    // MARK: - Playback

    private func play(_ data: Data) async throws {
        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(data: data)
        } catch {
            throw ProviderError.decoding(String(localized: "The speech server's audio could not be played."))
        }
        player.delegate = self
        self.player = player
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            if !player.play() { finish() }
        }
    }

    private func finish() {
        continuation?.resume()
        continuation = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finish() }
    }

    /// Splits at paragraph ends, then sentence ends, never inside a word.
    static func pieces(of text: String, limit: Int) -> [String] {
        var pieces: [String] = []
        var current = ""
        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { pieces.append(trimmed) }
            current = ""
        }
        for paragraph in text.components(separatedBy: "\n") {
            if current.count + paragraph.count > limit { flush() }
            if paragraph.count <= limit {
                current += paragraph + "\n"
                continue
            }
            paragraph.enumerateSubstrings(in: paragraph.startIndex..., options: .bySentences) { sentence, _, _, _ in
                guard let sentence else { return }
                if current.count + sentence.count > limit { flush() }
                current += sentence
            }
            current += "\n"
        }
        flush()
        return pieces
    }
}
