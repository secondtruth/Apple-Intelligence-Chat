//
//  MarkdownDocument.swift
//  Apple Intelligence Chat
//

import Foundation

/// A reply parsed into blocks. Foundation's Markdown parser already knows
/// lists, fenced code, quotes and tables; it reports them as presentation
/// intents on a flat attributed string, and this type folds them back into a
/// tree a view can lay out. No package is involved, and an unterminated fence —
/// the normal state of a reply that is still streaming — parses as a code block.
struct MarkdownDocument: Equatable, Sendable {
    indirect enum Block: Equatable, Sendable {
        case paragraph(AttributedString)
        case heading(level: Int, AttributedString)
        case code(language: String?, String)
        case quote([Block])
        case list(ordered: Bool, items: [ListItem])
        case table(Table)
        case rule
    }

    struct ListItem: Equatable, Sendable {
        var ordinal: Int
        var blocks: [Block]
    }

    struct Table: Equatable, Sendable {
        enum Alignment: Equatable, Sendable { case leading, center, trailing }

        var alignments: [Alignment]
        var header: [AttributedString]
        var rows: [[AttributedString]]
    }

    var blocks: [Block]

    init(_ source: String) {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: source, options: options) else {
            blocks = [.paragraph(AttributedString(source))]
            return
        }
        blocks = Self.blocks(of: Self.tree(from: parsed))
    }

    // MARK: - Folding intents into a tree

    private final class Node {
        let kind: PresentationIntent.Kind?
        let identity: Int
        var children: [Node] = []
        var text = AttributedString()

        init(kind: PresentationIntent.Kind?, identity: Int) {
            self.kind = kind
            self.identity = identity
        }
    }

    private static func tree(from parsed: AttributedString) -> Node {
        let root = Node(kind: nil, identity: 0)
        for run in parsed.runs {
            // Components come innermost first; the tree is built outside in.
            let path = run.presentationIntent?.components.reversed() ?? []
            var node = root
            for component in path {
                if let last = node.children.last, last.identity == component.identity {
                    node = last
                } else {
                    let child = Node(kind: component.kind, identity: component.identity)
                    node.children.append(child)
                    node = child
                }
            }

            var piece = AttributedString(parsed[run.range])
            // Models break lines where they mean a line break. CommonMark
            // would join them with a space; the reply reads wrong that way.
            if run.inlinePresentationIntent?.contains(.softBreak) == true {
                piece = AttributedString("\n")
            }
            piece.presentationIntent = nil
            node.text.append(piece)
        }
        return root
    }

    private static func blocks(of node: Node) -> [Block] {
        // Text outside any block only occurs for input without structure.
        if node.kind == nil, node.children.isEmpty, !node.text.characters.isEmpty {
            return [.paragraph(node.text)]
        }
        return node.children.compactMap(block)
    }

    private static func block(_ node: Node) -> Block? {
        switch node.kind {
        case .paragraph:
            return .paragraph(node.text)
        case .header(let level):
            return .heading(level: level, node.text)
        case .codeBlock(let languageHint):
            var code = String(node.text.characters)
            while code.hasSuffix("\n") { code.removeLast() }
            let language = languageHint?.trimmingCharacters(in: .whitespaces)
            return .code(language: language?.isEmpty == false ? language : nil, code)
        case .thematicBreak:
            return .rule
        case .blockQuote:
            return .quote(blocks(of: node))
        case .orderedList, .unorderedList:
            let items = node.children.map { item -> ListItem in
                var ordinal = 0
                if case .listItem(let value) = item.kind { ordinal = value }
                return ListItem(ordinal: ordinal, blocks: blocks(of: item))
            }
            if case .orderedList = node.kind { return .list(ordered: true, items: items) }
            return .list(ordered: false, items: items)
        case .table(let columns):
            var table = Table(
                alignments: columns.map { column in
                    switch column.alignment {
                    case .center: .center
                    case .right: .trailing
                    default: .leading
                    }
                },
                header: [],
                rows: [])
            for row in node.children {
                let cells = row.children.map(\.text)
                if case .tableHeaderRow = row.kind {
                    table.header = cells
                } else {
                    table.rows.append(cells)
                }
            }
            return .table(table)
        default:
            return node.text.characters.isEmpty ? nil : .paragraph(node.text)
        }
    }

    // MARK: - Speech

    /// The reply as it should be read aloud: no markup, and no code, which a
    /// voice turns into a recital of punctuation.
    var spokenText: String {
        Self.spoken(blocks).joined(separator: "\n")
    }

    private static func spoken(_ blocks: [Block]) -> [String] {
        blocks.flatMap { block -> [String] in
            switch block {
            case .paragraph(let text), .heading(_, let text):
                return [String(text.characters)]
            case .code, .rule:
                return []
            case .quote(let inner):
                return spoken(inner)
            case .list(_, let items):
                return items.flatMap { spoken($0.blocks) }
            case .table(let table):
                return ([table.header] + table.rows).map { row in
                    row.map { String($0.characters) }.joined(separator: ", ")
                }
            }
        }
    }
}
