//
//  TextServicesProvider.swift
//  Apple Intelligence Chat
//

#if os(macOS)
import AppKit

/// Backs the Services menu entries declared in Info.plist, so a selection in
/// any app can be rewritten, summarized or translated in place.
@MainActor
final class TextServicesProvider: NSObject {
    private let runner: TextActionRunner
    private let onAsk: (String) -> Void

    init(runner: TextActionRunner, onAsk: @escaping (String) -> Void) {
        self.runner = runner
        self.onAsk = onAsk
        super.init()
    }

    // MARK: - Service entry points

    @objc func rewriteSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        transform(.rewrite, pasteboard: pasteboard, error: error)
    }

    @objc func summarizeSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        transform(.summarize, pasteboard: pasteboard, error: error)
    }

    @objc func translateSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        transform(.translate, pasteboard: pasteboard, error: error)
    }

    @objc func askAboutSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let selection = pasteboard.string(forType: .string), !selection.isEmpty else {
            error.pointee = NSString(string: TextActionRunner.RunError.emptySelection.localizedDescription)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        onAsk(selection)
    }

    // MARK: - Plumbing

    private func transform(_ role: TextActionRole, pasteboard: NSPasteboard, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let selection = pasteboard.string(forType: .string) else {
            error.pointee = NSString(string: TextActionRunner.RunError.emptySelection.localizedDescription)
            return
        }

        switch awaitResult(timeout: 110, { [runner] in
            do { return .success(try await runner.run(role, on: selection)) }
            catch { return .failure(error) }
        }) {
        case .success(let text):
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        case .failure(let failure):
            error.pointee = NSString(string: failure.localizedDescription)
        case nil:
            error.pointee = NSString(string: String(localized: "The model took too long to answer."))
        }
    }

    /// A service method has to hand the result back before it returns, but the
    /// work is async and runs on this very actor. Blocking would deadlock, so
    /// the run loop is pumped instead — that lets the awaiting task proceed
    /// while the Services machinery waits.
    private func awaitResult(
        timeout: TimeInterval,
        _ operation: @escaping () async -> Result<String, Error>
    ) -> Result<String, Error>? {
        var outcome: Result<String, Error>?
        Task { @MainActor in outcome = await operation() }

        let deadline = Date().addingTimeInterval(timeout)
        while outcome == nil, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return outcome
    }
}

/// Keeps the provider alive: NSApplication does not retain it.
@MainActor
enum ServicesHost {
    private static var provider: TextServicesProvider?

    static func install(_ provider: TextServicesProvider) {
        guard Self.provider == nil else { return }
        Self.provider = provider
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()
    }
}
#endif
