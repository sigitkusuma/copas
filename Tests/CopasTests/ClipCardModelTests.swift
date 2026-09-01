import Foundation
import Testing

@testable import Copas

struct ClipCardModelTests {

    static let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func text(_ string: String, at offset: TimeInterval = 0) -> ClipRecord {
        ClipRecord.text(
            string,
            source: SourceApp(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
            at: Self.now.addingTimeInterval(offset)
        ) { _ in "" }
    }

    @Test func aTextCardCountsItsLinesAndCharacters() {
        let card = ClipCardModel(text("one\ntwo\nthree"), now: Self.now)
        #expect(card.lineCount == 3)
        #expect(card.charCount == 13)
        #expect(card.detail == "3 lines · 13 characters")
    }

    @Test func aSingleLineDoesNotAdvertiseItsLineCount() {
        #expect(ClipCardModel(text("hello"), now: Self.now).detail == "5 characters")
    }

    /// Counting lines would mean reading the blob, once per card, on the main
    /// thread. The footer says less rather than costing that.
    @Test func textLivingInABlobReportsCharactersOnly() {
        let long = String(repeating: "x", count: ClipRecord.inlineByteLimit + 10)
        let record = ClipRecord.text(long, at: Self.now) { ContentHash.hex(of: $0) }
        let card = ClipCardModel(record, now: Self.now)

        #expect(card.lineCount == nil)
        #expect(card.detail.hasSuffix("characters"))
    }

    @Test func anImageCardShowsItsDimensionsAndSize() {
        let record = ClipRecord.image(
            blobKey: ContentHash.hex(of: "i"),
            thumbKey: nil,
            contentHash: ContentHash.hex(of: "i"),
            byteSize: 2_400_000,
            pixelWidth: 2_560,
            pixelHeight: 1_440,
            at: Self.now
        )
        #expect(ClipCardModel(record, now: Self.now).detail == "2560 × 1440 · 2.3 MB")
    }

    @Test func sizesAreReadableAtEveryScale() {
        #expect(ClipCardModel.byteString(512) == "512 B")
        #expect(ClipCardModel.byteString(2_048) == "2 KB")
        #expect(ClipCardModel.byteString(5 * 1_024 * 1_024) == "5.0 MB")
    }

    @Test func codeIsMarkedForAMonospacedFace() {
        #expect(ClipCardModel(text("if (x > 0) { return true; }"), now: Self.now).isMonospaced)
        #expect(!ClipCardModel(text("Remember to buy milk on the way home"), now: Self.now).isMonospaced)
    }

    /// Images never get the code treatment — their preview is empty, and a
    /// heuristic reading an empty string is a coin toss.
    @Test func imagesAreNeverMonospaced() {
        let record = ClipRecord.image(
            blobKey: ContentHash.hex(of: "i"),
            thumbKey: nil,
            contentHash: ContentHash.hex(of: "i"),
            byteSize: 1,
            pixelWidth: 1,
            pixelHeight: 1
        )
        #expect(!ClipCardModel(record, now: Self.now).isMonospaced)
    }
}

struct ClipSectionBuilderTests {

    static let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func text(_ string: String, daysAgo: Int) -> ClipRecord {
        ClipRecord.text(
            string,
            at: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Self.now)!
        ) { _ in "" }
    }

    @Test func clipsAreGroupedByDayInTheOrderTheyArrive() {
        let sections = ClipSectionBuilder.sections(
            from: [
                text("a", daysAgo: 0),
                text("b", daysAgo: 0),
                text("c", daysAgo: 1),
                text("d", daysAgo: 5),
            ],
            now: Self.now
        )

        #expect(sections.count == 3)
        #expect(sections.map(\.label).prefix(2) == ["Today", "Yesterday"])
        #expect(sections[0].cards.map(\.preview) == ["a", "b"])
        #expect(sections[1].cards.map(\.preview) == ["c"])
    }

    /// Grouping is one pass over records that are already ordered, so two clips
    /// from the same day must never produce two sections.
    @Test func oneDayIsOneSection() {
        let sections = ClipSectionBuilder.sections(
            from: (0..<6).map { text("clip \($0)", daysAgo: 0) },
            now: Self.now
        )
        #expect(sections.count == 1)
        #expect(sections[0].cards.count == 6)
    }

    @Test func noClipsMeansNoSections() {
        #expect(ClipSectionBuilder.sections(from: [], now: Self.now).isEmpty)
    }
}
