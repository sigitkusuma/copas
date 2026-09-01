import Carbon.HIToolbox
import Testing

@testable import Copas

struct KeyCombinationTests {

    @Test func theDefaultShortcutReadsAsItDoesInMenus() {
        #expect(KeyCombination.showBoard.displayString == "⇧⌘V")
        #expect(KeyCombination.captureToText.displayString == "⇧⌘2")
    }

    /// macOS writes modifiers in a fixed order, and a shortcut that prints them
    /// in any other order looks like a different shortcut.
    @Test func modifiersArePrintedInTheSystemOrder() {
        let all = KeyCombination(keyCode: 0x00, modifiers: [.command, .shift, .option, .control])
        #expect(all.displayString == "⌃⌥⇧⌘A")
    }

    @Test func modifiersAreTranslatedForCarbon() {
        let combination = KeyCombination(keyCode: 0x09, modifiers: [.command, .shift])
        #expect(combination.carbonModifiers == UInt32(cmdKey) | UInt32(shiftKey))
        #expect(KeyCombination(keyCode: 0, modifiers: []).carbonModifiers == 0)
    }

    @Test func namedKeysAreSpelledOut() {
        #expect(KeyCombination(keyCode: 0x31, modifiers: [.option]).displayString == "⌥Space")
        #expect(KeyCombination(keyCode: 0x35, modifiers: []).displayString == "⎋")
    }

    @Test func anUnmappedKeyStillRendersSomething() {
        #expect(KeyCombination(keyCode: 0x6F, modifiers: []).displayString == "Key 111")
    }
}
