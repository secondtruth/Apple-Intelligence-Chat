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

        // The system's language, not Locale.current: that follows the app's
        // English-only localization and would listen for English on a German Mac.
        let systemLocale = Locale.preferredLanguages.first.map(Locale.init(identifier:)) ?? .current
        let recognizer = SFSpeechRecognizer(locale: systemLocale) ?? SFSpeechRecognizer(locale: .current)
        guard let recognizer, recognizer.isAvailable else {
            throw VoiceInputError.recognizerUnavailable
        }

        speechRecognizer = recognizer
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest else {
            throw VoiceInputError.recognizerUnavailable
        }

        recognitionRequest.shouldReportPartialResults = true
        // The permission prompt promises transcription on this device; without
        // this the audio may be sent to Apple. Languages without an on-device
        // model still fall back to the server.
        recognitionRequest.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

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
