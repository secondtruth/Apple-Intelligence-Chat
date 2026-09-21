//
//  GlobalHotkey.swift
//  Apple Intelligence Chat
//

#if os(macOS)
import AppKit
import Carbon.HIToolbox

/// A system-wide shortcut. Carbon's hot-key API is the one route that works
/// from inside the sandbox without the Accessibility permission, so it is worth
/// the dated C interface.
@MainActor
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    /// ⌃⌥Space. Fixed for now; a recorder in Settings would be the next step.
    static let defaultKeyCode = UInt32(kVK_Space)
    static let defaultModifiers = UInt32(controlKey | optionKey)

    private(set) var isRegistered = false

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?

    private init() {}

    func register(
        keyCode: UInt32 = GlobalHotkey.defaultKeyCode,
        modifiers: UInt32 = GlobalHotkey.defaultModifiers,
        action: @escaping () -> Void
    ) {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.id == GlobalHotkey.identifier.id else { return noErr }
            DispatchQueue.main.async { GlobalHotkey.shared.fire() }
            return noErr
        }, 1, &eventType, nil, &eventHandler)

        let status = RegisterEventHotKey(
            keyCode, modifiers, Self.identifier,
            GetApplicationEventTarget(), 0, &hotKeyRef)
        isRegistered = status == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        isRegistered = false
    }

    fileprivate func fire() {
        action?()
    }

    /// 'AICh' — the signature only has to be unique within this process.
    private static let identifier = EventHotKeyID(signature: 0x41494368, id: 1)

    static var displayShortcut: String { "⌃⌥Space" }
}
#endif
