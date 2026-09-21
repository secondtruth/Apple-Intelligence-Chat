//
//  ModelPicker.swift
//  Apple Intelligence Chat
//

import SwiftUI

/// Chooses who answers the next message. It lives in the composer, beside
/// Send, because that is the question it settles; the on-device model and the
/// server's models are one list, so switching is a single act.
struct ModelPicker: View {
    @Environment(ProviderRegistry.self) private var registry
#if os(macOS)
    @Environment(\.openSettings) private var openSettings
#endif

    var body: some View {
        Menu {
            Section("On This Mac") {
                item(.onDevice, title: ProviderKind.appleIntelligence.displayName)
            }

            Section("Server · \(registry.serverHost)") {
                if registry.serverModels.isEmpty {
                    if registry.isRefreshing {
                        Text("Checking…")
                    } else if registry.serverError != nil {
                        Text("Not reachable")
                    } else {
                        Text("No models installed")
                    }
                } else {
                    ForEach(registry.serverModels, id: \.self) { model in
                        item(.server(model: model), title: model)
                    }
                }
            }

            Divider()
            Button("Check Again") { registry.refresh() }
#if os(macOS)
            Button("Server Settings…") {
                UserDefaults.standard.set(SettingsPane.chatServer.rawValue, forKey: SettingsPane.selectionKey)
                openSettings()
            }
#endif
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbolName)
                    .foregroundStyle(isUnavailable ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                Text(registry.choiceLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.callout)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(.rect)
            .accessibilityElement(children: .ignore)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .help("Choose who answers")
        .accessibilityLabel("Model")
        .accessibilityValue(registry.choiceLabel)
    }

    private func item(_ choice: ModelChoice, title: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { registry.choice == choice },
            set: { isOn in if isOn { registry.select(choice) } }))
    }

    private var isUnavailable: Bool {
        if case .unavailable = registry.availability { return true }
        return false
    }

    private var symbolName: String {
        isUnavailable ? "exclamationmark.triangle.fill" : registry.kind.symbolName
    }
}
