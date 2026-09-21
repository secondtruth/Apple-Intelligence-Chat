//
//  SettingsView.swift
//  Apple Intelligence Chat
//

import SwiftUI

/// Where answers come from and how they are generated.
struct SettingsView: View {
    @Environment(ProviderRegistry.self) private var registry
    @Environment(ConversationStore.self) private var store
    @Environment(PromptLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var confirmDeleteAll = false
    @AppStorage("quickAskHotkeyEnabled") private var quickAskHotkeyEnabled = true

    var body: some View {
        Form {
            Section("Answers From") {
                Picker("Provider", selection: providerBinding) {
                    ForEach(ProviderKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                availabilityRow
            }

            if registry.kind == .openAICompatible {
                Section("Server") {
                    TextField("Base URL", text: baseURLBinding, prompt: Text("http://localhost:11434/v1"))
                        .textContentType(.URL)
#if os(iOS)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
#endif
                    SecureField("API Key", text: apiKeyBinding, prompt: Text("Optional"))

                    HStack {
                        if registry.models.isEmpty {
                            Text("Model")
                            Spacer()
                            Text("No models found")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Model", selection: modelBinding) {
                                ForEach(registry.models, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                        }
                        Button("Reload", systemImage: "arrow.clockwise") { registry.refresh() }
                            .labelStyle(.iconOnly)
                            .disabled(registry.isRefreshing)
                    }

                    Text("Works with Ollama, llama.cpp, LM Studio and any other server that speaks the OpenAI chat-completions API. For Ollama, run `ollama serve` and keep the default address.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Generation") {
                Toggle("Stream Responses", isOn: streamBinding)
                VStack(alignment: .leading) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(temperatureBinding.wrappedValue, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: temperatureBinding, in: 0.0...2.0, step: 0.05)
                }
                .padding(.vertical, 2)
            }

            Section("System Instructions") {
                TextEditor(text: instructionsBinding)
                    .frame(minHeight: 90)
                    .font(.body)
                Text("Changing this starts a fresh model session for every conversation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Quick Ask") {
                Toggle("Global Shortcut", isOn: $quickAskHotkeyEnabled)
                    .onChange(of: quickAskHotkeyEnabled) { _, enabled in
#if os(macOS)
                        if enabled {
                            GlobalHotkey.shared.register { QuickAskController.shared.toggle() }
                        } else {
                            GlobalHotkey.shared.unregister()
                        }
#endif
                    }
                Text("Press \(GlobalHotkey.displayShortcut) anywhere to ask without switching apps.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Text Actions") {
                Text("These run on the selected text from any app, through the Services menu, and on the clipboard from the menu bar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(TextActionRole.allCases) { role in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Instructions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: instructionsBinding(for: role))
                                .frame(minHeight: 54)

                            Text("Prompt — \(PromptTemplate.placeholder) is replaced by the text")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: templateBinding(for: role))
                                .frame(minHeight: 72)

                            Button("Restore Default") { library.reset(role) }
                                .controlSize(.small)
                                .disabled(!library.isCustomized(role))
                        }
                        .padding(.top, 4)
                    } label: {
                        Label(role.title, systemImage: role.symbolName)
                    }
                }
            }

            Section {
                Button("Delete All Conversations", role: .destructive) {
                    confirmDeleteAll = true
                }
                .disabled(store.conversations.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 520)
        .navigationTitle("Settings")
        .confirmationDialog("Delete all conversations?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) {
                store.deleteAll()
                store.saveNow()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .onAppear { registry.refresh() }
#if !os(macOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
#endif
    }

    private var availabilityRow: some View {
        HStack(spacing: 8) {
            switch registry.availability {
            case .checking:
                ProgressView().controlSize(.small)
                Text("Checking…").foregroundStyle(.secondary)
            case .available:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Ready")
            case .unavailable(let reason, let recovery):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reason)
                    if let recovery {
                        Text(recovery).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .font(.callout)
    }

    // MARK: - Bindings into the observable registry

    private var providerBinding: Binding<ProviderKind> {
        Binding(get: { registry.kind }, set: { registry.kind = $0 })
    }

    private var baseURLBinding: Binding<String> {
        Binding(
            get: { registry.openAIConfiguration.baseURL },
            set: { registry.openAIConfiguration.baseURL = $0 })
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { registry.openAIConfiguration.apiKey },
            set: { registry.openAIConfiguration.apiKey = $0 })
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { registry.openAIConfiguration.model },
            set: { registry.openAIConfiguration.model = $0 })
    }

    private var streamBinding: Binding<Bool> {
        Binding(get: { registry.settings.stream }, set: { registry.settings.stream = $0 })
    }

    private var temperatureBinding: Binding<Double> {
        Binding(get: { registry.settings.temperature }, set: { registry.settings.temperature = $0 })
    }

    private var instructionsBinding: Binding<String> {
        Binding(
            get: { registry.settings.systemInstructions },
            set: { registry.settings.systemInstructions = $0 })
    }

    private func instructionsBinding(for role: TextActionRole) -> Binding<String> {
        Binding(
            get: { library.prompt(for: role).instructions },
            set: { value in
                var prompt = library.prompt(for: role)
                prompt.instructions = value
                library.set(prompt, for: role)
            })
    }

    private func templateBinding(for role: TextActionRole) -> Binding<String> {
        Binding(
            get: { library.prompt(for: role).template },
            set: { value in
                var prompt = library.prompt(for: role)
                prompt.template = value
                library.set(prompt, for: role)
            })
    }
}
