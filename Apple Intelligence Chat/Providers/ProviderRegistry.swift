//
//  ProviderRegistry.swift
//  Apple Intelligence Chat
//

import Foundation
import Observation

/// Holds the providers, the settings they share and the readiness of whichever
/// one is selected. Views read the state here instead of asking a backend.
@MainActor
@Observable
final class ProviderRegistry {
    let apple = AppleIntelligenceProvider()
    let openAI = OpenAICompatibleProvider()

    private(set) var availability: ProviderAvailability = .checking
    private(set) var models: [String] = []
    private(set) var isRefreshing = false

    private var refreshTask: Task<Void, Never>?

    var kind: ProviderKind {
        didSet {
            guard kind != oldValue else { return }
            Defaults.providerKind = kind.rawValue
            refresh()
        }
    }

    var settings: GenerationSettings {
        didSet {
            guard settings != oldValue else { return }
            Defaults.useStreaming = settings.stream
            Defaults.temperature = settings.temperature
            Defaults.systemInstructions = settings.systemInstructions
            // A changed instruction invalidates the on-device sessions, which
            // bake the instructions in at creation.
            if settings.systemInstructions != oldValue.systemInstructions {
                instructionsDidChange?()
            }
        }
    }

    var openAIConfiguration: OpenAICompatibleProvider.Configuration {
        didSet {
            guard openAIConfiguration != oldValue else { return }
            openAI.configuration = openAIConfiguration
            Defaults.openAIBaseURL = openAIConfiguration.baseURL
            Defaults.openAIModel = openAIConfiguration.model
            KeychainStore.write(openAIConfiguration.apiKey, account: "openai-compatible")
            if kind == .openAICompatible { refresh(debounce: .milliseconds(600)) }
        }
    }

    /// Called when the system instructions change, so open conversations drop
    /// their cached sessions.
    var instructionsDidChange: (() -> Void)?

    var current: ChatProvider {
        switch kind {
        case .appleIntelligence: apple
        case .openAICompatible: openAI
        }
    }

    /// What the chat pane shows under the composer when nothing can answer.
    var statusMessage: String? {
        guard case .unavailable(let reason, let recovery) = availability else { return nil }
        guard let recovery else { return reason }
        return "\(reason) \(recovery)"
    }

    init() {
        kind = ProviderKind(rawValue: Defaults.providerKind) ?? .appleIntelligence
        settings = GenerationSettings(
            systemInstructions: Defaults.systemInstructions,
            temperature: Defaults.temperature,
            stream: Defaults.useStreaming)
        openAIConfiguration = OpenAICompatibleProvider.Configuration(
            baseURL: Defaults.openAIBaseURL,
            apiKey: KeychainStore.read("openai-compatible"),
            model: Defaults.openAIModel)
        openAI.configuration = openAIConfiguration
        refresh()
    }

    /// Re-checks the selected provider. Typing in the address field debounces
    /// so every keystroke does not open a connection.
    func refresh(debounce: Duration = .zero) {
        refreshTask?.cancel()
        refreshTask = Task {
            if debounce > .zero {
                try? await Task.sleep(for: debounce)
                guard !Task.isCancelled else { return }
            }
            isRefreshing = true
            availability = .checking
            let provider = current
            let result = await provider.refreshAvailability()
            let discovered = await provider.availableModels()
            guard !Task.isCancelled else { return }
            availability = result
            models = discovered
            isRefreshing = false

            // A server that offers exactly one model needs no picking.
            if kind == .openAICompatible, openAIConfiguration.model.isEmpty, discovered.count == 1 {
                openAIConfiguration.model = discovered[0]
            }
        }
    }

    private enum Defaults {
        @UserDefault("providerKind", default: ProviderKind.appleIntelligence.rawValue)
        static var providerKind: String

        @UserDefault("useStreaming", default: true)
        static var useStreaming: Bool

        @UserDefault("temperature", default: 0.7)
        static var temperature: Double

        @UserDefault("systemInstructions", default: "You are a helpful assistant.")
        static var systemInstructions: String

        @UserDefault("openAIBaseURL", default: OpenAICompatibleProvider.Configuration.ollamaDefault.baseURL)
        static var openAIBaseURL: String

        @UserDefault("openAIModel", default: "")
        static var openAIModel: String
    }
}

/// Small property wrapper so the defaults keys live in one place instead of
/// being repeated as string literals across views.
@propertyWrapper
struct UserDefault<Value> {
    let key: String
    let defaultValue: Value

    init(_ key: String, default defaultValue: Value) {
        self.key = key
        self.defaultValue = defaultValue
    }

    var wrappedValue: Value {
        get { UserDefaults.standard.object(forKey: key) as? Value ?? defaultValue }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
