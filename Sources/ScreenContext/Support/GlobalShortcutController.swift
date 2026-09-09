import Carbon
import Foundation
import ScreenContextCore

final class GlobalShortcutController: @unchecked Sendable {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var registeredShortcut: GlobalShortcut?
    private var nextIdentifier: UInt32 = 1
    private let action: @Sendable () -> Void

    init(action: @escaping @Sendable () -> Void) {
        self.action = action
        var specification = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let controller = Unmanaged<GlobalShortcutController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                controller.action()
                return noErr
            },
            1,
            &specification,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    deinit {
        unregister()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    func register(_ shortcut: GlobalShortcut) -> Bool {
        guard shortcut.isValid else { return false }
        if registeredShortcut?.keyCode == shortcut.keyCode,
           registeredShortcut?.modifiers == shortcut.modifiers { return true }
        let identifier = EventHotKeyID(
            signature: OSType(0x4F4C4F4D),
            id: nextIdentifier
        )
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &replacement
        )
        guard status == noErr, let replacement else { return false }
        // Keep the previous shortcut working if the replacement is unavailable.
        unregister()
        hotKey = replacement
        registeredShortcut = shortcut
        nextIdentifier &+= 1
        return true
    }

    private func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
            registeredShortcut = nil
        }
    }
}
