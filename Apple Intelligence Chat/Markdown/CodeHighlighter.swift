//
//  CodeHighlighter.swift
//  Apple Intelligence Chat
//

import Foundation
import HighlightSwift

/// Colours code through highlight.js. One engine serves every code block, and
/// results are kept, because a lazy thread rebuilds its blocks while scrolling
/// and would otherwise highlight the same code again each time.
@MainActor
final class CodeHighlighter {
    static let shared = CodeHighlighter()

    private let engine = Highlight()
    private var cache: [Key: AttributedString] = [:]
    private var order: [Key] = []

    private struct Key: Hashable {
        let code: String
        let language: String?
        let isDark: Bool
    }

    func cached(_ code: String, language: String?, isDark: Bool) -> AttributedString? {
        cache[Key(code: code, language: language, isDark: isDark)]
    }

    func highlight(_ code: String, language: String?, isDark: Bool) async -> AttributedString? {
        let key = Key(code: code, language: language, isDark: isDark)
        if let hit = cache[key] { return hit }

        let colors: HighlightColors = isDark ? .dark(.xcode) : .light(.xcode)
        var result: AttributedString?
        if let language {
            result = try? await engine.attributedText(code, language: language, colors: colors)
        }
        // A fence may name a language highlight.js does not know, or none.
        if result == nil {
            result = try? await engine.attributedText(code, colors: colors)
        }
        guard let result else { return nil }

        cache[key] = result
        order.append(key)
        if order.count > 200 { cache[order.removeFirst()] = nil }
        return result
    }
}
