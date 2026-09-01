import Foundation
import Testing

@testable import Copas

struct ClipRepositoryTests {

    let repository: ClipRepository

    init() throws {
        repository = ClipRepository(database: try AppDatabase.inMemory())
    }

    // A fixed instant, so nothing here depends on when the suite runs.
    static let epoch = Date(timeIntervalSince1970: 1_760_000_000)

    private func at(_ offset: TimeInterval) -> Date {
        Self.epoch.addingTimeInterval(offset)
    }

    private func text(
        _ string: String,
        at date: Date,
        source: SourceApp = SourceApp(),
        id: String = UUID().uuidString
    ) -> ClipRecord {
        ClipRecord.text(string, source: source, at: date, id: id) { ContentHash.hex(of: $0) }
    }

    private func image(
        seed: String,
        at date: Date,
        id: String = UUID().uuidString
    ) -> ClipRecord {
        ClipRecord.image(
            blobKey: ContentHash.hex(of: seed),
            thumbKey: ContentHash.hex(of: seed) + ".jpg",
            contentHash: ContentHash.hex(of: seed),
            byteSize: 1_024,
            pixelWidth: 800,
            pixelHeight: 600,
            at: date,
            id: id
        )
    }

    // MARK: - Writing

    @Test func insertedClipsComeBack() throws {
        let record = text("hello", at: at(0))
        let outcome = try repository.insert(record)

        #expect(outcome.isNew)
        #expect(try repository.count() == 1)
        #expect(try repository.record(id: record.id)?.preview == "hello")
    }

    /// Copying the same thing twice should leave one card, freshly dated — and
    /// keep the id it already had, so anything holding a selection keeps it.
    @Test func identicalContentIsPromotedRatherThanDuplicated() throws {
        let first = text("shared", at: at(0), id: "first")
        let second = text("shared", at: at(60), id: "second")

        _ = try repository.insert(first)
        let outcome = try repository.insert(second)

        #expect(!outcome.isNew)
        #expect(outcome.record.id == "first")
        #expect(outcome.record.createdAt == at(60).timeIntervalSince1970)
        #expect(try repository.count() == 1)
        #expect(try repository.record(id: "second") == nil)
    }

    @Test func promotionAdoptsTheMostRecentSourceApp() throws {
        _ = try repository.insert(
            text("shared", at: at(0), source: SourceApp(bundleID: "com.apple.dt.Xcode", name: "Xcode"))
        )
        let outcome = try repository.insert(
            text("shared", at: at(60), source: SourceApp(bundleID: "com.apple.Safari", name: "Safari"))
        )
        #expect(outcome.record.sourceBundleID == "com.apple.Safari")
        #expect(outcome.record.sourceAppName == "Safari")
    }

    @Test func promotionKeepsTheKnownSourceWhenTheNewOneIsUnknown() throws {
        _ = try repository.insert(
            text("shared", at: at(0), source: SourceApp(bundleID: "com.apple.Safari", name: "Safari"))
        )
        let outcome = try repository.insert(text("shared", at: at(60)))
        #expect(outcome.record.sourceBundleID == "com.apple.Safari")
    }

    // MARK: - Paging

    @Test func pagesAreNewestFirst() throws {
        for index in 0..<5 {
            _ = try repository.insert(text("clip \(index)", at: at(TimeInterval(index) * 60)))
        }
        let page = try repository.page(limit: 5)
        #expect(page.map(\.preview) == ["clip 4", "clip 3", "clip 2", "clip 1", "clip 0"])
    }

    @Test func theCursorContinuesExactlyWhereThePageStopped() throws {
        for index in 0..<5 {
            _ = try repository.insert(text("clip \(index)", at: at(TimeInterval(index) * 60)))
        }
        let first = try repository.page(limit: 2)
        let second = try repository.page(limit: 2, before: ClipCursor(first[1]))

        #expect(first.map(\.preview) == ["clip 4", "clip 3"])
        #expect(second.map(\.preview) == ["clip 2", "clip 1"])
    }

    /// Two clips can land in the same instant — an import gives every row the
    /// same timestamp when the source had no better resolution. Paging on time
    /// alone would then repeat a row on one page and skip another.
    @Test func pagingBreaksTiesSoNoClipIsRepeatedOrSkipped() throws {
        let sameInstant = at(0)
        for index in 0..<6 {
            _ = try repository.insert(text("clip \(index)", at: sameInstant))
        }

        var seen: [String] = []
        var cursor: ClipCursor?
        for _ in 0..<3 {
            let page = try repository.page(limit: 2, before: cursor)
            seen += page.map(\.id)
            cursor = page.last.map(ClipCursor.init)
        }

        #expect(seen.count == 6)
        #expect(Set(seen).count == 6)
    }

    // MARK: - Search

    @Test func searchMatchesThePreview() throws {
        _ = try repository.insert(text("the quick brown fox", at: at(0)))
        _ = try repository.insert(text("lazy dog", at: at(60)))

        let hits = try repository.page(matching: .text("brown"), limit: 10)
        #expect(hits.map(\.preview) == ["the quick brown fox"])
    }

    @Test func searchMatchesOnAPrefixAsYouType() throws {
        _ = try repository.insert(text("refactoring", at: at(0)))
        #expect(try repository.page(matching: .text("refac"), limit: 10).count == 1)
    }

    /// The point of running OCR at all: an image with no text of its own becomes
    /// findable by what is written inside it.
    @Test func searchMatchesRecognizedText() throws {
        let picture = image(seed: "screenshot", at: at(0))
        _ = try repository.insert(picture)

        #expect(try repository.page(matching: .text("invoice"), limit: 10).isEmpty)

        _ = try repository.setRecognizedText("Invoice 4471 — total due", for: picture.id)

        let hits = try repository.page(matching: .text("invoice"), limit: 10)
        #expect(hits.map(\.id) == [picture.id])
    }

    @Test func clearingRecognizedTextTakesItOutOfSearchAgain() throws {
        let picture = image(seed: "screenshot", at: at(0))
        _ = try repository.insert(picture)
        _ = try repository.setRecognizedText("invoice", for: picture.id)
        let cleared = try repository.setRecognizedText(nil, for: picture.id)

        #expect(cleared?.recognizedAt == nil)
        #expect(try repository.page(matching: .text("invoice"), limit: 10).isEmpty)
    }

    @Test func deletingAClipTakesItOutOfSearch() throws {
        let record = text("findable", at: at(0))
        _ = try repository.insert(record)
        _ = try repository.delete(ids: [record.id])

        #expect(try repository.page(matching: .text("findable"), limit: 10).isEmpty)
    }

    /// FTS5 reads `AND`, `OR`, `NOT`, `*` and `"` as syntax. Typed into a search
    /// field they are just characters, and an unescaped one is a thrown error
    /// rather than an empty result.
    @Test func searchingForOperatorCharactersDoesNotThrow() throws {
        _ = try repository.insert(text("terms AND conditions", at: at(0)))

        #expect(try repository.page(matching: .text("AND"), limit: 10).count == 1)
        #expect(try repository.page(matching: .text("\""), limit: 10).count == 1)
        #expect(try repository.page(matching: .text("* OR *"), limit: 10).isEmpty)
    }

    @Test func searchIsScopedByKind() throws {
        _ = try repository.insert(text("report", at: at(0)))
        let picture = image(seed: "report-png", at: at(60))
        _ = try repository.insert(picture)
        _ = try repository.setRecognizedText("report", for: picture.id)

        let imagesOnly = ClipQuery(match: ClipQuery.matchExpression(for: "report"), kinds: [.image])
        #expect(try repository.page(matching: imagesOnly, limit: 10).map(\.id) == [picture.id])
        #expect(try repository.count(matching: imagesOnly) == 1)
    }

    @Test func searchIsScopedByApp() throws {
        _ = try repository.insert(
            text("note", at: at(0), source: SourceApp(bundleID: "com.apple.Safari", name: "Safari"))
        )
        _ = try repository.insert(
            text("note two", at: at(60), source: SourceApp(bundleID: "com.apple.dt.Xcode", name: "Xcode"))
        )

        let safariOnly = ClipQuery(bundleIDs: ["com.apple.Safari"])
        #expect(try repository.page(matching: safariOnly, limit: 10).map(\.preview) == ["note"])
    }

    // MARK: - Retention

    @Test func pruneKeepsTheNewestClipsUpToTheLimit() throws {
        for index in 0..<10 {
            _ = try repository.insert(text("clip \(index)", at: at(TimeInterval(index) * 60)))
        }
        let removed = try repository.prune(RetentionPolicy(maximumCount: 4))

        #expect(removed.count == 6)
        #expect(try repository.count() == 4)
        #expect(try repository.page(limit: 10).map(\.preview)
            == ["clip 9", "clip 8", "clip 7", "clip 6"])
    }

    @Test func pruneDropsClipsOlderThanTheAgeLimit() throws {
        _ = try repository.insert(text("ancient", at: at(0)))
        _ = try repository.insert(text("recent", at: at(3_600)))

        let removed = try repository.prune(
            RetentionPolicy(maximumAge: 1_800),
            now: at(3_600)
        )

        #expect(removed.map(\.preview) == ["ancient"])
        #expect(try repository.page(limit: 10).map(\.preview) == ["recent"])
    }

    @Test func pruneWithNoLimitsRemovesNothing() throws {
        _ = try repository.insert(text("keep me", at: at(0)))
        #expect(try repository.prune(.unlimited).isEmpty)
        #expect(try repository.count() == 1)
    }

    @Test func pruneOnAnEmptyHistoryIsHarmless() throws {
        #expect(try repository.prune(.default).isEmpty)
    }

    // MARK: - Import

    /// What makes the Settings "re-run import" button safe to press.
    @Test func importingTheSameClipsTwiceChangesNothing() throws {
        let records = (0..<3).map { text("legacy \($0)", at: at(TimeInterval($0)), id: "legacy-\($0)") }

        let first = try repository.importRecords(records)
        let second = try repository.importRecords(records)

        #expect(first == ImportSummary(imported: 3, skipped: 0, degraded: 0))
        #expect(second == ImportSummary(imported: 0, skipped: 3, degraded: 0))
        #expect(try repository.count() == 3)
    }

    @Test func importSkipsContentAlreadyCapturedUnderADifferentID() throws {
        _ = try repository.insert(text("shared", at: at(0), id: "captured"))
        let summary = try repository.importRecords([text("shared", at: at(60), id: "imported")])

        #expect(summary.skipped == 1)
        #expect(try repository.count() == 1)
        #expect(try repository.record(id: "captured") != nil)
    }

    // MARK: - Deletion and file keys

    @Test func deleteReportsWhatItRemoved() throws {
        let keep = text("keep", at: at(0))
        let drop = text("drop", at: at(60))
        _ = try repository.insert(keep)
        _ = try repository.insert(drop)

        let removed = try repository.delete(ids: [drop.id, "not-a-real-id"])

        #expect(removed.map(\.preview) == ["drop"])
        #expect(try repository.count() == 1)
    }

    @Test func liveKeysListEveryReferencedFile() throws {
        let picture = image(seed: "one", at: at(0))
        _ = try repository.insert(picture)
        _ = try repository.insert(text("small", at: at(60)))

        let keys = try repository.liveKeys()
        #expect(keys.blobs == [picture.blobKey!])
        #expect(keys.thumbnails == [picture.thumbKey!])
    }

    @Test func setRecognizedTextOnAMissingClipReturnsNil() throws {
        #expect(try repository.setRecognizedText("x", for: "nope") == nil)
    }
}
