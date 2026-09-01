import Carbon.HIToolbox
import Foundation

/// A global shortcut: one key plus its modifiers.
struct KeyCombination: Sendable, Equatable, Codable {

    struct Modifiers: OptionSet, Sendable, Equatable, Codable {
        let rawValue: Int
        init(rawValue: Int) { self.rawValue = rawValue }

        static let command = Modifiers(rawValue: 1 << 0)
        static let shift = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 2)
        static let control = Modifiers(rawValue: 1 << 3)
    }

    /// A virtual key code, which is positional rather than a character: `0x09`
    /// is the key where `V` sits on a US layout and stays that physical key on
    /// AZERTY. That is the right identity for a shortcut.
    var keyCode: UInt16
    var modifiers: Modifiers

    init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⇧⌘V — the shortcut the app this replaces used, kept so the muscle memory
    /// survives the switch.
    static let showBoard = KeyCombination(keyCode: 0x09, modifiers: [.command, .shift])

    /// ⇧⌘2, for capturing a region and reading text out of it.
    static let captureToText = KeyCombination(keyCode: 0x13, modifiers: [.command, .shift])

    /// Carbon wants its own modifier bitfield, in its own order.
    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        return value
    }

    /// In the order macOS writes them in menus: ⌃⌥⇧⌘.
    var displayString: String {
        var parts = ""
        if modifiers.contains(.control) { parts += "⌃" }
        if modifiers.contains(.option) { parts += "⌥" }
        if modifiers.contains(.shift) { parts += "⇧" }
        if modifiers.contains(.command) { parts += "⌘" }
        return parts + Self.keyName(for: keyCode)
    }

    /// Names for the keys a shortcut is likely to use.
    ///
    /// Deliberately not derived from the current keyboard layout: a menu that
    /// renamed itself when the user switched input source would be worse than
    /// one that is occasionally wrong about a letter.
    static func keyName(for keyCode: UInt16) -> String {
        if let named = namedKeys[keyCode] { return named }
        return letters[keyCode] ?? "Key \(keyCode)"
    }

    private static let namedKeys: [UInt16: String] = [
        0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x35: "⎋",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
    ]

    private static let letters: [UInt16: String] = [
        0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F",
        0x05: "G", 0x04: "H", 0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L",
        0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P", 0x0C: "Q", 0x0F: "R",
        0x01: "S", 0x11: "T", 0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X",
        0x10: "Y", 0x06: "Z",
        0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4",
        0x17: "5", 0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9",
    ]
}
