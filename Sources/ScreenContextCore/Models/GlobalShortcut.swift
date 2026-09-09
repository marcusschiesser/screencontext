import Carbon
import Foundation

public struct GlobalShortcut: Codable, Equatable, Sendable {
    public let keyCode: UInt16
    public let modifiers: UInt32
    public let keyDisplayName: String

    public init(keyCode: UInt16, modifiers: UInt32, keyDisplayName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyDisplayName = keyDisplayName
    }

    public static let defaultShortcut = GlobalShortcut(
        keyCode: UInt16(kVK_ANSI_R),
        modifiers: UInt32(cmdKey | controlKey),
        keyDisplayName: "R"
    )

    public var isValid: Bool {
        let supportedModifiers = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        return keyCode < 128
            && !(54...63).contains(keyCode)
            && keyCode != UInt16(kVK_Escape)
            && modifiers & UInt32(cmdKey | controlKey | optionKey) != 0
            && modifiers & ~supportedModifiers == 0
            && !keyDisplayName.isEmpty
            && keyDisplayName.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    public var displayName: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + keyDisplayName
    }
}
