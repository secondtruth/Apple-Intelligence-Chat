//
//  AppleIntelligenceProvider.swift
//  Apple Intelligence Chat
//

import Foundation
import FoundationModels

/// Talks to the on-device model. A `LanguageModelSession` carries the thread's
/// context itself, so one session is kept per conversation and only the newest
/// prompt is sent.
@MainActor
final class AppleIntelligenceProvider: ChatProvider {
    let kind: ProviderKind = .appleIntelligence

    private let model = SystemLanguageModel.default
    private var sessions: [UUID: LanguageModelSession] = [:]
    private var instructions: [UUID: String] = [:]

    func refreshAvailability() async -> ProviderAvailability {
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable(
                    reason: String(localized: "This Mac cannot run Apple Intelligence."),
                    recovery: nil)
            case .appleIntelligenceNotEnabled:
                return .unavailable(
                    reason: String(localized: "Apple Intelligence is turned off."),
                    recovery: String(localized: "Enable it in System Settings › Apple Intelligence & Siri."))
            case .modelNotReady:
                return .unavailable(
                    reason: String(localized: "The model is still downloading."),
                    recovery: String(localized: "Stay online and on power; this finishes in the background."))
            @unknown default:
                return .unavailable(reason: String(localized: "The model is unavailable."), recovery: nil)
            }
        @unknown default:
            return .unavailable(reason: String(localized: "The model is unavailable."), recovery: nil)
        }
    }

    func availableModels() async -> [String] { [] }

    func forget(conversation id: UUID) {
        sessions[id] = nil
        instructions[id] = nil
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    let session = session(for: request)
                    let options = GenerationOptions(temperature: request.settings.temperature)
                    let prompt = request.latestPrompt
                    guard !prompt.isEmpty else {
                        continuation.finish()
                        return
                    }

                    if request.settings.stream {
                        for try await partial in session.streamResponse(to: prompt, options: options) {
                            try Task.checkCancellation()
                            continuation.yield(.replace(partial.content))
                        }
                    } else {
                        let response = try await session.respond(to: prompt, options: options)
                        continuation.yield(.replace(response.content))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Returns the conversation's session, rebuilding it when the system
    /// instructions changed — a session bakes them in at creation — or when
    /// none is cached, which is the case for every thread reopened after a
    /// restart. The rebuild replays the stored thread as a transcript, so the
    /// model keeps the context the sidebar still shows.
    private func session(for request: ChatRequest) -> LanguageModelSession {
        let wanted = request.settings.systemInstructions
        if let existing = sessions[request.conversationID], instructions[request.conversationID] == wanted {
            return existing
        }
        let session = LanguageModelSession(transcript: transcript(for: request))
        sessions[request.conversationID] = session
        instructions[request.conversationID] = wanted
        return session
    }

    private func transcript(for request: ChatRequest) -> Transcript {
        var entries: [Transcript.Entry] = []

        let instructions = request.settings.systemInstructions
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty {
            entries.append(.instructions(.init(
                segments: [.text(.init(content: instructions))],
                toolDefinitions: [])))
        }

        // Everything except the turn we are about to send.
        for message in request.history.dropLast() where !message.text.isEmpty {
            let segments: [Transcript.Segment] = [.text(.init(content: message.text))]
            switch message.role {
            case .user:
                entries.append(.prompt(.init(segments: segments)))
            case .assistant:
                entries.append(.response(.init(assetIDs: [], segments: segments)))
            }
        }

        return Transcript(entries: entries)
    }
}
