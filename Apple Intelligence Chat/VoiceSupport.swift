//
//  VoiceSupport.swift
//  Apple Intelligence Chat
//
//  Created by Codex on 6/10/25.
//

import AVFoundation
import Observation
import Speech

enum VoiceInputError: LocalizedError {
    case speechRecognitionDenied
    case microphoneDenied
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .speechRecognitionDenied:
            return "Speech recognition access was denied."
        case .microphoneDenied:
            return "Microphone access was denied."
        case .recognizerUnavailable:
            return "Speech recognition is currently unavailable."
        }
    }
}

@MainActor
@Observable
final class VoiceInputController: NSObject {
    var isRecording = false

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?

    func toggleRecording(onTranscript: @escaping (String) -> Void) async throws {
        if isRecording {
            stopRecording()
            return
        }

        try await startRecording(onTranscript: onTranscript)
    }

    func stopRecording() {
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

#if os(iOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif

        isRecording = false
    }

    private func startRecording(onTranscript: @escaping (String) -> Void) async throws {
        let speechAuthorization = await requestSpeechAuthorization()
        guard speechAuthorization == .authorized else {
            throw VoiceInputError.speechRecognitionDenied
        }

        let hasMicrophoneAccess = await requestMicrophoneAccess()
        guard hasMicrophoneAccess else {
            throw VoiceInputError.microphoneDenied
        }

        stopRecording()

        let recognizer = SFSpeechRecognizer(locale: .current)
        guard let recognizer, recognizer.isAvailable else {
            throw VoiceInputError.recognizerUnavailable
        }

        speechRecognizer = recognizer
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest else {
            throw VoiceInputError.recognizerUnavailable
        }

        recognitionRequest.shouldReportPartialResults = true

#if os(iOS) || os(visionOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
#endif

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let result {
                Task { @MainActor in
                    onTranscript(result.bestTranscription.formattedString)
                }
            }

            if error != nil || result?.isFinal == true {
                Task { @MainActor in
                    self.stopRecording()
                }
            }
        }
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophoneAccess() async -> Bool {
#if os(macOS)
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
#else
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
#endif
    }
}

@MainActor
@Observable
final class SpeechOutputController: NSObject, AVSpeechSynthesizerDelegate {
    var speakingMessageID: ChatMessage.ID?

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggleSpeaking(for message: ChatMessage) {
        if speakingMessageID == message.id {
            stopSpeaking()
        } else {
            speak(message)
        }
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        speakingMessageID = nil
    }

    private func speak(_ message: ChatMessage) {
        // Read the reply, not its markup: no asterisks, no backticks, no code.
        let text = MarkdownDocument(message.text).spokenText
        guard !text.isEmpty else { return }
        speakingMessageID = message.id
        utter(text, voice: VoiceCatalog.voice(for: text))
    }

    /// Lets Settings play a voice before it is chosen.
    func preview(_ voice: AVSpeechSynthesisVoice?, sample: String) {
        speakingMessageID = nil
        utter(sample, voice: voice ?? VoiceCatalog.voice(for: sample))
    }

    private func utter(_ text: String, voice: AVSpeechSynthesisVoice?) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speakingMessageID = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.speakingMessageID = nil
        }
    }
}
