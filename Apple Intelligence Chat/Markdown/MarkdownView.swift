//
//  MarkdownView.swift
//  Apple Intelligence Chat
//

import SwiftUI

/// Renders a reply as blocks. Equatable on its source, because the thread
/// re-evaluates every visible message for each streamed token and only the
/// one that changed should be parsed again.
struct MarkdownView: View, Equatable {
    let text: String

    var body: some View {
        MarkdownBlocks(blocks: MarkdownDocument(text).blocks)
    }
}

private struct MarkdownBlocks: View {
    let blocks: [MarkdownDocument.Block]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Positions are stable identities here: a streaming reply only
            // ever grows at its end.
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                view(for: block)
                    .padding(.top, extraSpace(above: block, at: index))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A heading belongs to what follows it, so it keeps more distance from
    /// what came before.
    private func extraSpace(above block: MarkdownDocument.Block, at index: Int) -> CGFloat {
        if case .heading = block, index > 0 { return 6 }
        return 0
    }

    @ViewBuilder
    private func view(for block: MarkdownDocument.Block) -> some View {
        switch block {
        case .paragraph(let text):
            Text(Self.styled(text))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let text):
            Text(Self.styled(text))
                .font(Self.headingFont(level))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .code(let language, let code):
            CodeBlockView(language: language, code: code)
        case .quote(let inner):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.quaternary)
                    .frame(width: 3)
                MarkdownBlocks(blocks: inner)
                    .foregroundStyle(.secondary)
            }
        case .list(let ordered, let items):
            ListBlockView(ordered: ordered, items: items)
        case .table(let table):
            TableBlockView(table: table)
        case .rule:
            Divider().padding(.vertical, 2)
        }
    }

    // Chat-sized: a reply is not a document, and its headings should not
    // outweigh the conversation around them.
    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title3.weight(.semibold)
        case 2: .headline
        default: .subheadline.weight(.semibold)
        }
    }

    /// Inline code gets the monospaced face one step down and a faint ground,
    /// so an identifier reads as one without shouting over the sentence.
    static func styled(_ text: AttributedString) -> AttributedString {
        var result = text
        for run in result.runs where run.inlinePresentationIntent?.contains(.code) == true {
            result[run.range].font = .system(.callout, design: .monospaced)
            result[run.range].backgroundColor = .secondary.opacity(0.16)
        }
        return result
    }
}

private struct ListBlockView: View {
    let ordered: Bool
    let items: [MarkdownDocument.ListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ordered ? "\(item.ordinal)." : "•")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: markerWidth, alignment: .trailing)
                    MarkdownBlocks(blocks: item.blocks)
                }
            }
        }
    }

    /// Wide enough for the longest ordinal, so item texts share one edge.
    private var markerWidth: CGFloat {
        guard ordered else { return 12 }
        let digits = String(items.map(\.ordinal).max() ?? 1).count
        return CGFloat(digits) * 8 + 6
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var highlighted: AttributedString?

    /// While a reply streams, the code grows faster than it is highlighted.
    /// The coloured part stays and the rest follows plain, instead of the
    /// whole block flickering between the two.
    private var displayed: AttributedString {
        guard let highlighted else { return AttributedString(code) }
        let done = String(highlighted.characters)
        guard code.hasPrefix(done) else { return AttributedString(code) }
        return highlighted + AttributedString(String(code.dropFirst(done.count)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let language {
                    Text(language)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CopyButton(text: code, help: "Copy this code")
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)

            Divider()

            // Code scrolls sideways rather than wrapping: a wrapped line
            // cannot be told from two lines.
            ScrollView(.horizontal) {
                Text(displayed)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    // Without it the scroll view's height proposal cuts the
                    // code down to its first line.
                    .fixedSize()
                    .padding(12)
            }
        }
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        .task(id: HighlightRequest(code: code, isDark: colorScheme == .dark)) {
            let isDark = colorScheme == .dark
            if let hit = CodeHighlighter.shared.cached(code, language: language, isDark: isDark) {
                highlighted = hit
                return
            }
            // Streaming restarts this task per token; only a pause gets coloured.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            if let result = await CodeHighlighter.shared.highlight(code, language: language, isDark: isDark),
               !Task.isCancelled {
                highlighted = result
            }
        }
    }

    private struct HighlightRequest: Equatable {
        let code: String
        let isDark: Bool
    }
}

private struct TableBlockView: View {
    let table: MarkdownDocument.Table

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                        Text(MarkdownBlocks.styled(cell))
                            .fontWeight(.semibold)
                            .gridColumnAlignment(alignment(of: column))
                    }
                }
                Divider()
                ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(MarkdownBlocks.styled(cell))
                                .monospacedDigit()
                        }
                    }
                    if index < table.rows.count - 1 {
                        Divider().opacity(0.5)
                    }
                }
            }
            .textSelection(.enabled)
            .padding(.vertical, 2)
        }
    }

    private func alignment(of column: Int) -> HorizontalAlignment {
        guard table.alignments.indices.contains(column) else { return .leading }
        switch table.alignments[column] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}
