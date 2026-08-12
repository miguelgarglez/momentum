#if os(macOS)
import AppKit
import Carbon

/// Global hotkey via Carbon — does not require Accessibility.
@MainActor
final class HotKeyController {
    var onToggle: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x4D4F4D54), id: 1) // 'MOMT'

    /// Default: ⌃⌥⌘M (Control-Option-Command-M)
    func registerDefault() {
        unregister()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData else { return noErr }
                let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if hotKeyID.id == controller.hotKeyID.id {
                    Task { @MainActor in
                        controller.onToggle?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )

        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        let keyCode = UInt32(kVK_ANSI_M)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    deinit {
        // Best-effort; MainActor isolation may not hold in deinit.
    }
}
#endif
