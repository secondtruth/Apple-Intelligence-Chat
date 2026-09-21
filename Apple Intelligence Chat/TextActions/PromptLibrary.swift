//
//  PromptLibrary.swift
//  Apple Intelligence Chat
//

import Foundation
import Observation

/// The text actions the app offers system-wide. The set is fixed because the
/// Services menu is declared in Info.plist at build time; what each one asks
/// the model is editable.
enum TextActionRole: String, CaseIterable, Identifiable, Codable, Sendable {
    case rewrite
    case summarize
    case translate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rewrite: String(localized: "Rewrite")
        case .summarize: String(localized: "Summarize")
        case .translate: String(localized: "Translate")
        }
    }

    var symbolName: String {
        switch self {
        case .rewrite: "pencil.and.outline"
        case .summarize: "text.line.first.and.arrowtriangle.forward"
        case .translate: "character.bubble"
        }
    }

    var defaultPrompt: PromptTemplate {
        switch self {
        case .rewrite:
            PromptTemplate(
                instructions: "You rewrite text. Answer with the rewritten text only — no preamble, no quotes, no commentary.",
                template: "Rewrite the following text so it reads clearly and naturally. Keep its language, meaning and tone.\n\n{{selection}}")
        case .summarize:
            PromptTemplate(
                instructions: "You summarize text. Answer with the summary only — no preamble, no quotes, no commentary.",
                template: "Summarize the following text in a few sentences, in the language it is written in.\n\n{{selection}}")
        case .translate:
            PromptTemplate(
                instructions: "You translate text. Answer with the translation only — no preamble, no quotes, no commentary.",
                template: "Translate the following text to German. If it is already German, translate it to English.\n\n{{selection}}")
        }
    }
}

/// What one action sends to the model. `template` carries the placeholder
/// `{{selection}}`; without it the selection is appended, so an edited prompt
/// cannot silently drop the text it is supposed to act on.
struct PromptTemplate: Codable, Equatable, Sendable {
    var instructions: String
    var template: String

    static let placeholder = "{{selection}}"

    func rendered(with selection: String) -> String {
        guard template.contains(Self.placeholder) else {
            return template.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + selection
        }
        return template.replacingOccurrences(of: Self.placeholder, with: selection)
    }
}

@MainActor
@Observable
final class PromptLibrary {
    private(set) var prompts: [TextActionRole: PromptTemplate]

    private static let defaultsKey = "textActionPrompts"

    init() {
        prompts = Self.load()
    }

    func prompt(for role: TextActionRole) -> PromptTemplate {
        prompts[role] ?? role.defaultPrompt
    }

    func set(_ prompt: PromptTemplate, for role: TextActionRole) {
        prompts[role] = prompt
        save()
    }

    func reset(_ role: TextActionRole) {
        prompts[role] = role.defaultPrompt
        save()
    }

    func isCustomized(_ role: TextActionRole) -> Bool {
        prompt(for: role) != role.defaultPrompt
    }

    private func save() {
        let storable = Dictionary(uniqueKeysWithValues: prompts.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(storable) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static func load() -> [TextActionRole: PromptTemplate] {
        var result: [TextActionRole: PromptTemplate] = [:]
        for role in TextActionRole.allCases { result[role] = role.defaultPrompt }

        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode([String: PromptTemplate].self, from: data)
        else { return result }

        for (key, value) in stored {
            guard let role = TextActionRole(rawValue: key) else { continue }
            result[role] = value
        }
        return result
    }
}
