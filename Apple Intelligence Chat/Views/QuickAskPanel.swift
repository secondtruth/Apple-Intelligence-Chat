//
//  QuickAskPanel.swift
//  Apple Intelligence Chat
//

#if os(macOS)
import AppKit
import SwiftUI

/// A panel has to opt in to keyboard focus, otherwise the prompt field cannot
/// be typed into.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The window the global shortcut opens: ask something without leaving the app
/// you are in, read the answer, take it or drop it.
@MainActor
final class QuickAskController: NSObject, NSWindowDelegate {
    static let shared = QuickAskController()

    private var panel: NSPanel?
    private var runner: TextActionRunner?
    private var registry: ProviderRegistry?
    private var openInChat: ((String) -> Void)?
    private var anchor: NSPoint?

    private override init() {}

    func configure(
        runner: TextActionRunner,
        registry: ProviderRegistry,
        openInChat: @escaping (String) -> Void
    ) {
        self.runner = runner
        self.registry = registry
        self.openInChat = openInChat
    }

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let runner, let registry else { return }

        let panel = self.panel ?? makePanel(runner: runner, registry: registry)
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        // The hosting controller only settles on its fitting size once it has
        // laid out; placing before that centres a window of width zero.
        panel.layoutIfNeeded()
        place(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel(runner: TextActionRunner, registry: ProviderRegistry) -> NSPanel {
        let view = QuickAskView(
            runner: runner,
            onClose: { [weak self] in self?.hide() },
            onOpenInChat: { [weak self] text in
                self?.hide()
                self?.openInChat?(text)
            })
            .environment(registry)

        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 92),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.contentViewController = controller
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    /// Spotlight's position: horizontally centred on the screen holding the
    /// pointer, the top edge a fifth of the way down.
    private func place(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let top = NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.maxY - visible.height * 0.2)
        anchor = top
        panel.setFrameTopLeftPoint(top)
    }

    /// An answer makes the panel taller. Windows grow from their bottom-left
    /// corner, which would walk the prompt up the screen, so the top edge is
    /// put back where it was.
    func windowDidResize(_ notification: Notification) {
        guard let panel, let anchor else { return }
        panel.setFrameTopLeftPoint(anchor)
    }
}

struct QuickAskView: View {
    let runner: TextActionRunner
    let onClose: () -> Void
    let onOpenInChat: (String) -> Void

    @Environment(ProviderRegistry.self) private var registry

    @State private var question = ""
    @State private var answer = ""
    @State private var failure: String?
    @State private var isRunning = false
    @State private var task: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            prompt
            if !answer.isEmpty || failure != nil {
                Divider()
                result
            }
        }
        .frame(width: 620)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onExitCommand { close() }
        .onAppear { isFocused = true }
    }

    private var prompt: some View {
        HStack(spacing: 12) {
            Image(systemName: registry.kind.symbolName)
                .font(.title3)
                .foregroundStyle(.tint)

            TextField("Ask the local model…", text: $question)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isFocused)
                .onSubmit { isRunning ? stop() : ask() }

            if isRunning {
                Button(action: stop) {
                    Image(systemName: "stop.circle.fill")
                }
                .buttonStyle(.plain)
                .help("Stop")
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(answer)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: 280)

            HStack(spacing: 8) {
                Text(registry.kind.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !answer.isEmpty {
                    Button("Copy") { copy() }
                    Button("Open in Chat") { onOpenInChat(question) }
                }
                Button("Close") { close() }
                    .keyboardShortcut(.cancelAction)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Actions

    private func ask() {
        let prompt = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isRunning else { return }

        answer = ""
        failure = nil
        isRunning = true

        task = Task {
            do {
                _ = try await runner.ask(prompt) { partial in answer = partial }
            } catch is CancellationError {
                // Keep whatever arrived before the stop.
            } catch {
                failure = error.localizedDescription
            }
            isRunning = false
            task = nil
        }
    }

    private func stop() {
        task?.cancel()
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
    }

    private func close() {
        stop()
        onClose()
        question = ""
        answer = ""
        failure = nil
    }
}
#endif
