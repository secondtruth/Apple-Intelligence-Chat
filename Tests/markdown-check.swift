// Checks MarkdownDocument without an Xcode test target. Run from the repo root:
//   swiftc -parse-as-library "Apple Intelligence Chat/Markdown/MarkdownDocument.swift" Tests/markdown-check.swift -o "$TMPDIR/markdown-check" && "$TMPDIR/markdown-check"
import Foundation

@main
struct MarkdownCheck {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if condition { print("ok    \(label)") } else { failures += 1; print("FAIL  \(label)") }
    }

    static func plain(_ text: AttributedString) -> String { String(text.characters) }

    static func main() {
        typealias Block = MarkdownDocument.Block

        let reply = MarkdownDocument("""
        # Fixing it
        First line
        second line with **bold**.

        1. **Install** it:
           ```bash
           brew install foo
           ```
        2. Second
           - nested a
           - nested b

        > quoted *text*

        | Name | Qty |
        |:-----|----:|
        | a | 1 |

        ---
        """).blocks

        expect(reply.count == 6, "six top-level blocks")
        if case .heading(let level, let text) = reply[0] {
            expect(level == 1 && plain(text) == "Fixing it", "heading")
        } else { expect(false, "heading") }

        if case .paragraph(let text) = reply[1] {
            expect(plain(text) == "First line\nsecond line with bold.", "soft break kept as a line break")
        } else { expect(false, "paragraph") }

        if case .list(let ordered, let items) = reply[2] {
            expect(ordered && items.map(\.ordinal) == [1, 2], "ordered list keeps ordinals")
            if case .code(let language, let code) = items[0].blocks.last {
                expect(language == "bash" && code == "brew install foo", "code block nested in a list item")
            } else { expect(false, "code block nested in a list item") }
            if case .list(let innerOrdered, let inner) = items[1].blocks.last {
                expect(!innerOrdered && inner.count == 2, "nested unordered list")
            } else { expect(false, "nested unordered list") }
        } else { expect(false, "list") }

        if case .quote(let inner) = reply[3], case .paragraph(let text) = inner.first {
            expect(plain(text) == "quoted text", "block quote")
        } else { expect(false, "block quote") }

        if case .table(let table) = reply[4] {
            expect(table.header.map(plain) == ["Name", "Qty"], "table header")
            expect(table.rows.map { $0.map(plain) } == [["a", "1"]], "table rows")
            expect(table.alignments == [.leading, .trailing], "table alignments")
        } else { expect(false, "table") }

        expect(reply[5] == .rule, "thematic break")

        // The state of every streamed reply at some point.
        let streaming = MarkdownDocument("Run this:\n\n```swift\nlet x = 1\nlet y").blocks
        if case .code(let language, let code) = streaming.last {
            expect(language == "swift" && code == "let x = 1\nlet y", "unterminated fence is a code block")
        } else { expect(false, "unterminated fence is a code block") }

        expect(MarkdownDocument("").blocks.isEmpty, "empty input")
        expect(MarkdownDocument("plain words").blocks == [.paragraph(AttributedString("plain words"))], "plain text")

        let spoken = MarkdownDocument("Use `ls`:\n\n```sh\nls -la\n```\n\n- **one**\n- two").spokenText
        expect(spoken == "Use ls:\none\ntwo", "speech drops markup and code")

        print(failures == 0 ? "all checks passed" : "\(failures) check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
