//
//  MessageView.swift
//  Apple Intelligence Chat
//

import SwiftUI

/// A single chat bubble. Assistant replies render as Markdown, carry hover
/// actions and, when generation failed, an inline retry.
struct MessageView: View {
    let message: ChatMessage
    let isStreaming: Bool
    let isSpeaking: Bool
    var onSpeak: (() -> Void)?
    var onRetry: (() -> Void)?

    @State private var isHovering = false
    @State private var didCopy = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 48)
                userBubble
            } else {
                assistantBubble
                Spacer(minLength: 48)
            }
        }
        .padding(.vertical, 6)
        .onHover { isHovering = $0 }
    }

    // MARK: - Bubbles

    private var userBubble: some View {
        Text(message.text)
            .textSelection(.enabled)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .foregroundStyle(.white)
            .background(.tint, in: .rect(cornerRadius: 18))
            .glassEffect(in: .rect(cornerRadius: 18))
    }

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.text.isEmpty && message.failure == nil {
                PulsingDotView()
                    .frame(width: 60, height: 25)
            } else if !message.text.isEmpty {
                Text(markdown)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let failure = message.failure {
                failureNotice(failure)
            }

            if !message.text.isEmpty {
                actions
                    .opacity(isHovering || isSpeaking ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: isHovering)
                    .animation(.easeInOut(duration: 0.15), value: isSpeaking)
            }
        }
        .padding(.vertical, 2)
    }

    /// Inline rather than an alert: a failed answer belongs where the answer
    /// would have been, and the thread stays readable behind it.
    private func failureNotice(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let onRetry {
                    Button("Try Again", systemImage: "arrow.clockwise", action: onRetry)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }

    private var actions: some View {
        HStack(spacing: 2) {
            Button {
                copy()
            } label: {
                Label(didCopy ? "Copied" : "Copy",
                      systemImage: didCopy ? "checkmark" : "doc.on.doc")
            }
            .help("Copy this reply")

            if let onSpeak {
                Button(action: onSpeak) {
                    Label(isSpeaking ? "Stop" : "Speak",
                          systemImage: isSpeaking ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .help(isSpeaking ? "Stop speaking" : "Speak this reply")
            }

            if let onRetry, message.failure == nil, !isStreaming {
                Button(action: onRetry) {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
                .help("Answer again")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .font(.callout)
    }

    // MARK: - Helpers

    /// Inline-only parsing keeps the line breaks a chat reply relies on;
    /// full-document parsing would collapse them.
    private var markdown: AttributedString {
        (try? AttributedString(
            markdown: message.text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(message.text)
    }

    private func copy() {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
#else
        UIPasteboard.general.string = message.text
#endif
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}

/// Animated loading indicator shown while the model is generating.
struct PulsingDotView: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { index in
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundStyle(.primary.opacity(0.5))
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .opacity(isAnimating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
    }
}
