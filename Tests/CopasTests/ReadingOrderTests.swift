import CoreGraphics
import Foundation
import Testing

@testable import Copas

struct ReadingOrderTests {

    /// Vision's coordinate space: normalised, origin bottom-left, so a larger
    /// `y` is higher up the page.
    private func box(x: CGFloat, y: CGFloat, width: CGFloat = 0.2, height: CGFloat = 0.05) -> CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    @Test func nothingToOrder() {
        #expect(ReadingOrder.rowMajor([]).isEmpty)
        #expect(ReadingOrder.rowMajor([box(x: 0.1, y: 0.1)]) == [0])
    }

    @Test func aSingleColumnIsReadTopToBottom() {
        let boxes = [
            box(x: 0.1, y: 0.2),
            box(x: 0.1, y: 0.8),
            box(x: 0.1, y: 0.5),
        ]
        #expect(ReadingOrder.rowMajor(boxes) == [1, 2, 0])
    }

    /// The case this exists for. Vision reads a two-column layout column-major —
    /// every label, then every value — which pairs "Hotkey" with "History size"
    /// instead of with the shortcut beside it. On a settings pane or a table,
    /// which is most of what a clipboard manager sees, that is simply wrong.
    @Test func atwoColumnLayoutPairsEachLabelWithItsValue() {
        let labels = ["Hotkey", "History size", "Launch at login", "Status bar"]
        let values = ["⇧⌘V", "500 items", "Enabled", "Visible"]
        let rows: [CGFloat] = [0.80, 0.60, 0.40, 0.20]

        // Input in Vision's order: the whole left column, then the whole right.
        var boxes = rows.map { box(x: 0.10, y: $0) }
        boxes += rows.map { box(x: 0.60, y: $0) }
        let text = labels + values

        let read = ReadingOrder.rowMajor(boxes).map { text[$0] }

        #expect(read == [
            "Hotkey", "⇧⌘V",
            "History size", "500 items",
            "Launch at login", "Enabled",
            "Status bar", "Visible",
        ])
    }

    /// Text on one line is rarely aligned to the pixel — a bold label beside
    /// lighter value text sits slightly differently — so a tolerance below half a
    /// line height would split one row into two.
    @Test func slightlyMisalignedTextStaysOnOneRow() {
        let boxes = [
            box(x: 0.10, y: 0.500, height: 0.05),
            box(x: 0.60, y: 0.512, height: 0.05),
        ]
        #expect(ReadingOrder.rowMajor(boxes) == [0, 1])
    }

    @Test func genuinelySeparateLinesStaySeparate() {
        let boxes = [
            box(x: 0.60, y: 0.30, height: 0.05),
            box(x: 0.10, y: 0.50, height: 0.05),
        ]
        // Far apart vertically, so the lower one must not be pulled up into the
        // upper one's row just because it sits to the right.
        #expect(ReadingOrder.rowMajor(boxes) == [1, 0])
    }

    /// A heading beside body text: the tolerance scales with the taller box, so
    /// mixed sizes on one line still read as one line.
    @Test func mixedTextSizesOnOneLineStillGroup() {
        let boxes = [
            box(x: 0.10, y: 0.50, height: 0.09),
            box(x: 0.55, y: 0.52, height: 0.04),
        ]
        #expect(ReadingOrder.rowMajor(boxes) == [0, 1])
    }
}

struct TextRecognizerLanguageTests {

    /// The bug this fixes was lopsided and easy to miss: Latin scripts share a
    /// recogniser and were unaffected, while a Japanese screenshot returned an
    /// empty string.
    @Test func thePreferredLanguageComesFirst() {
        let resolved = TextRecognizer.languages(
            preferred: ["ja-JP", "en-US"],
            supported: ["en-US", "ja-JP", "zh-Hans"]
        )
        #expect(resolved == ["ja-JP", "en-US"])
    }

    /// Code, URLs, file paths and UI chrome are English in most screenshots
    /// whatever the prose around them is.
    @Test func englishIsAlwaysKept() {
        #expect(TextRecognizer.languages(preferred: ["fr-FR"], supported: ["en-US", "fr-FR"])
            == ["fr-FR", "en-US"])
    }

    @Test func anUnsupportedLanguageFallsBackRatherThanFailing() {
        #expect(TextRecognizer.languages(preferred: ["id-ID"], supported: ["en-US", "ja-JP"])
            == ["en-US"])
    }

    @Test func regionVariantsMatchTheirBaseLanguage() {
        #expect(TextRecognizer.languages(preferred: ["en-GB"], supported: ["en-US"]) == ["en-US"])
        #expect(TextRecognizer.languages(preferred: ["zh_Hans_CN"], supported: ["zh-Hans", "en-US"])
            == ["zh-Hans", "en-US"])
    }

    @Test func aLanguageIsNeverListedTwice() {
        let resolved = TextRecognizer.languages(
            preferred: ["en-US", "en-GB", "en"],
            supported: ["en-US"]
        )
        #expect(resolved == ["en-US"])
    }

    @Test func knowingNothingStillProducesAUsableList() {
        #expect(TextRecognizer.languages(preferred: [], supported: []) == ["en-US"])
    }

    /// The list handed to Vision has to be one this machine actually supports,
    /// or recognition fails outright rather than degrading.
    @Test func thisMachineSupportsWhatWeWouldAskItFor() {
        let supported = TextRecognizer.supportedLanguages()
        let asked = TextRecognizer.languages(preferred: Locale.preferredLanguages, supported: supported)

        #expect(!asked.isEmpty)
        #expect(asked.allSatisfy { supported.contains($0) } || supported == ["en-US"])
    }
}
