//
//  SystemWidePanes.swift
//  Apple Intelligence Chat
//

import SwiftUI

struct QuickAskPane: View {
    @AppStorage("quickAskHotkeyEnabled") private var isEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $isEnabled) {
                    SettingLabel("Global Shortcut",
                                 detail: String(localized: "Press \(GlobalHotkey.displayShortcut) anywhere to ask without switching apps."))
                }
                    .onChange(of: isEnabled) { _, enabled in
#if os(macOS)
                        if enabled {
                            GlobalHotkey.shared.register { QuickAskController.shared.toggle() }
                        } else {
                            GlobalHotkey.shared.unregister()
                        }
#endif
                    }
            }
        }
    }
}

struct TextActionsPane: View {
    @Environment(PromptLibrary.self) private var library

    var body: some View {
        Form {
            Section {
                ForEach(TextActionRole.allCases) { role in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Instructions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: binding(for: role, \.instructions))
                                .frame(minHeight: 54)

                            Text("Prompt — \(PromptTemplate.placeholder) is replaced by the text")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: binding(for: role, \.template))
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
            } footer: {
                Text("These run on the selected text from any app, through the Services menu, and on the clipboard from the menu bar.")
            }
        }
    }

    private func binding(for role: TextActionRole, _ keyPath: WritableKeyPath<PromptTemplate, String>) -> Binding<String> {
        Binding(
            get: { library.prompt(for: role)[keyPath: keyPath] },
            set: { value in
                var prompt = library.prompt(for: role)
                prompt[keyPath: keyPath] = value
                library.set(prompt, for: role)
            })
    }
}
