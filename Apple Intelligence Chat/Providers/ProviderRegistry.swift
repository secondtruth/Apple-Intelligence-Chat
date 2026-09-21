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
    /// What the server offers, fetched whichever provider is selected, so the
    /// picker can list every possible answerer side by side.
    private(set) var serverModels: [String] = []
    /// Why the server's models could not be listed, nil while it answers.
    private(set) var serverError: String?
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
            refresh(debounce: .milliseconds(600))
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

    // MARK: - Model choice

    var choice: ModelChoice {
        switch kind {
        case .appleIntelligence: .onDevice
        case .openAICompatible: .server(model: openAIConfiguration.model)
        }
    }

    /// Switches provider and model in one step.
    func select(_ choice: ModelChoice) {
        switch choice {
        case .onDevice:
            kind = .appleIntelligence
        case .server(let model):
            openAIConfiguration.model = model
            kind = .openAICompatible
            // Picking from a list is deliberate; skip the typing debounce.
            refresh()
        }
    }

    /// Name of whatever answers the next message.
    var choiceLabel: String {
        switch kind {
        case .appleIntelligence:
            return ProviderKind.appleIntelligence.displayName
        case .openAICompatible:
            let model = openAIConfiguration.model
            return model.isEmpty ? String(localized: "Choose a Model") : model
        }
    }

    /// Host and port of the configured server, the part of the address that
    /// tells one server from another.
    var serverHost: String {
        guard let url = openAIConfiguration.normalizedBaseURL, let host = url.host else {
            return String(localized: "no address")
        }
        return url.port.map { "\(host):\($0)" } ?? host
    }

    var serverIsLocal: Bool {
        guard let host = openAIConfiguration.normalizedBaseURL?.host else { return false }
        return ["localhost", "127.0.0.1", "::1"].contains(host)
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
            // Concurrent, so a slow server cannot delay the on-device verdict.
            async let catalogue = Result { try await openAI.listModels() }
            let result = await provider.refreshAvailability()
            guard !Task.isCancelled else { return }
            availability = result
            let listing = await catalogue
            guard !Task.isCancelled else { return }
            let models = (try? listing.get()) ?? []
            serverModels = models
            if case .failure(let error) = listing {
                serverError = error.localizedDescription
            } else {
                serverError = nil
            }
            isRefreshing = false

            // A server that offers exactly one model needs no picking.
            if kind == .openAICompatible, openAIConfiguration.model.isEmpty, models.count == 1 {
                openAIConfiguration.model = models[0]
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
