//
//  AnswersPanes.swift
//  Apple Intelligence Chat
//

import SwiftUI

/// Where the server's models come from. Which model answers is the
/// composer's choice, not a setting; a server has to be configurable before
/// it can be picked there.
struct ChatServerPane: View {
    @Environment(ProviderRegistry.self) private var registry

    var body: some View {
        @Bindable var registry = registry

        Form {
            Section {
                TextField("Base URL", text: $registry.openAIConfiguration.baseURL,
                          prompt: Text("http://localhost:11434/v1"))
                    .textContentType(.URL)
#if os(iOS)
                    .autocapitalization(.none)
                    .keyboardType(.URL)
#endif
                SecureField("API Key", text: $registry.openAIConfiguration.apiKey, prompt: Text("Optional"))

                HStack(spacing: 8) {
                    status
                    Spacer()
                    Button("Check Again", systemImage: "arrow.clockwise") { registry.refresh() }
                        .labelStyle(.iconOnly)
                        .disabled(registry.isRefreshing)
                        .help("Check again")
                }
            } footer: {
                Text("Works with Ollama, llama.cpp, LM Studio and any other server that speaks the OpenAI chat-completions API. For Ollama, run `ollama serve` and keep the default address. Its models appear in the model menu below the message field.")
            }
        }
        .onAppear { registry.refresh() }
    }

    @ViewBuilder
    private var status: some View {
        if registry.isRefreshing {
            ProgressView().controlSize(.small)
            Text("Checking…").foregroundStyle(.secondary)
        } else if let error = registry.serverError {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(error)
        } else if registry.serverModels.isEmpty {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Reachable, but no models are installed.")
        } else {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Reachable, ^[\(registry.serverModels.count) model](inflect: true)")
        }
    }
}

struct GenerationPane: View {
    @Environment(ProviderRegistry.self) private var registry

    var body: some View {
        @Bindable var registry = registry

        Form {
            Section {
                Toggle(isOn: $registry.settings.stream) {
                    SettingLabel("Stream Responses",
                                 detail: String(localized: "Show an answer while it is being written."))
                }
                VStack(alignment: .leading) {
                    HStack(alignment: .firstTextBaseline) {
                        SettingLabel("Temperature",
                                     detail: String(localized: "Low values answer more predictably, high ones more freely."))
                        Spacer()
                        Text(registry.settings.temperature, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $registry.settings.temperature, in: 0.0...2.0, step: 0.05)
                }
                .padding(.vertical, 2)
            }

            Section {
                TextEditor(text: $registry.settings.systemInstructions)
                    .frame(minHeight: 120)
                    .font(.body)
            } header: {
                Text("System Instructions")
            } footer: {
                Text("Changing this starts a fresh model session for every conversation.")
            }
        }
    }
}
