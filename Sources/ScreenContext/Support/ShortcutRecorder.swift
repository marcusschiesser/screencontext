@preconcurrency import AppKit
import Carbon
import Observation
import ScreenContextCore

/// Captures key combinations before menu handling; SwiftUI owns the settings controls.
@MainActor
@Observable
final class ShortcutRecorder {
    private(set) var isRecording = false
    private(set) var needsModifier = false
    @ObservationIgnored private var eventMonitor: Any?
    @ObservationIgnored private var windowObserver: NSObjectProtocol?
    @ObservationIgnored private var completion: ((GlobalShortcut) -> Bool)?

    func start(completion: @escaping (GlobalShortcut) -> Bool) {
        stop()
        self.completion = completion
        isRecording = true
        needsModifier = false
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: NSApp.keyWindow,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func stop() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        eventMonitor = nil
        windowObserver = nil
        completion = nil
        isRecording = false
        needsModifier = false
    }

    /// The active Carbon hot key arrives here instead of in the local event monitor.
    @discardableResult
    func capture(_ shortcut: GlobalShortcut) -> Bool {
        guard isRecording else { return false }
        if completion?(shortcut) == true { stop() }
        return true
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }
        if event.keyCode == UInt16(kVK_Escape) {
            stop()
            return nil
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == UInt16(kVK_Tab), flags.intersection([.command, .control, .option]).isEmpty {
            stop()
            return event
        }
        guard !event.isARepeat else { return nil }
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let shortcut = GlobalShortcut(
            keyCode: event.keyCode,
            modifiers: modifiers,
            keyDisplayName: Self.keyDisplayName(for: event)
        )
        guard shortcut.isValid else {
            needsModifier = true
            return nil
        }
        needsModifier = false
        capture(shortcut)
        return nil
    }

    private static func keyDisplayName(for event: NSEvent) -> String {
        let specialKeys: [Int: String] = [
            kVK_Space: "␣", kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤",
            kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
            kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
            kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15",
            kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        ]
        return specialKeys[Int(event.keyCode)]
            ?? event.characters(byApplyingModifiers: [])?.uppercased()
            ?? ""
    }
}
