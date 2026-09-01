import Foundation
import Testing

@testable import Copas

final class ClipIngestorTests {

    let root: URL
    let clips: ClipRepository
    let blobs: BlobStore
    let thumbnails: ThumbnailStore
    let ingestor: ClipIngestor

    init() throws {
        root = try Fixtures.temporaryDirectory("ingest")
        clips = ClipRepository(database: try AppDatabase.inMemory())
        blobs = BlobStore(root: root.appendingPathComponent("blobs"))
        thumbnails = ThumbnailStore(root: root.appendingPathComponent("thumbs"), maximumPixelSize: 128)
        ingestor = ClipIngestor(clips: clips, blobs: blobs, thumbnails: thumbnails)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func payload(_ content: CapturedPayload.Content, at offset: TimeInterval = 0) -> CapturedPayload {
        CapturedPayload(
            content: content,
            source: SourceApp(bundleID: "com.apple.Safari", name: "Safari"),
            capturedAt: Date(timeIntervalSince1970: 1_760_000_000 + offset)
        )
    }

    @Test func textBecomesAnInlineClip() throws {
        let outcome = try #require(try ingestor.ingest(payload(.text(RichText(plain: "hello")))))

        #expect(outcome.isNew)
        #expect(outcome.record.isInline)
        #expect(outcome.record.inlineText == "hello")
        #expect(outcome.record.sourceBundleID == "com.apple.Safari")
        #expect(outcome.record.kind == .text)
    }

    @Test func oversizedTextIsMovedToABlobIntact() throws {
        let long = String(repeating: "x", count: ClipRecord.inlineByteLimit + 500)
        let outcome = try #require(try ingestor.ingest(payload(.text(RichText(plain: long)))))
        let key = try #require(outcome.record.blobKey)

        #expect(!outcome.record.isInline)
        #expect(try blobs.data(for: key) == Data(long.utf8))
    }

    @Test func richerFormatsAreStoredAndReferenced() throws {
        let rtf = Data("{\\rtf1 bold}".utf8)
        let html = Data("<b>bold</b>".utf8)
        let outcome = try #require(try ingestor.ingest(
            payload(.text(RichText(plain: "bold", rtf: rtf, html: html)))
        ))

        let rtfKey = try #require(outcome.record.rtfKey)
        let htmlKey = try #require(outcome.record.htmlKey)
        #expect(try blobs.data(for: rtfKey) == rtf)
        #expect(try blobs.data(for: htmlKey) == html)
        #expect(outcome.record.referencedBlobKeys.count == 2)
    }

    /// If the sweep only looked at `blob_key`, these files would be collected
    /// while the clip that needs them is still on screen.
    @Test func richTextBlobsSurviveTheGarbageSweep() throws {
        _ = try ingestor.ingest(payload(.text(RichText(
            plain: "bold",
            rtf: Data("{\\rtf1 bold}".utf8),
            html: Data("<b>bold</b>".utf8)
        ))))

        let live = try clips.liveKeys()
        #expect(live.blobs.count == 2)
        #expect(try blobs.collectGarbage(keeping: live.blobs) == 0)
    }

    @Test func anImageGetsABlobAThumbnailAndItsDimensions() throws {
        let png = Fixtures.pngData(width: 400, height: 200)
        let outcome = try #require(try ingestor.ingest(payload(.image(png))))
        let record = outcome.record

        #expect(record.kind == .image)
        #expect(record.pixelWidth == 400)
        #expect(record.pixelHeight == 200)
        #expect(record.byteSize == png.count)
        #expect(try blobs.data(for: #require(record.blobKey)) == png)
        #expect(thumbnails.contains(try #require(record.thumbKey)))
    }

    @Test func bytesThatAreNotAnImageAreDiscarded() throws {
        #expect(try ingestor.ingest(payload(.image(Data("not a picture".utf8)))) == nil)
        #expect(try clips.count() == 0)
    }

    @Test func emptyTextIsDiscarded() throws {
        #expect(try ingestor.ingest(payload(.text(RichText(plain: "")))) == nil)
        #expect(try clips.count() == 0)
    }

    @Test func copyingTheSameThingTwiceLeavesOneClip() throws {
        _ = try ingestor.ingest(payload(.text(RichText(plain: "again")), at: 0))
        let second = try #require(try ingestor.ingest(payload(.text(RichText(plain: "again")), at: 60)))

        #expect(!second.isNew)
        #expect(try clips.count() == 1)
        #expect(second.record.createdAt == 1_760_000_060)
    }
}
