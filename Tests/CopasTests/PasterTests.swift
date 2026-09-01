import AppKit
import Foundation
import Testing

@testable import Copas

@MainActor
final class PasterTests {

    let root: URL
    let pasteboard = Fixtures.pasteboard()
    let blobs: BlobStore
    let paster: Paster

    init() throws {
        root = try Fixtures.temporaryDirectory("paste")
        blobs = BlobStore(root: root.appendingPathComponent("blobs"))
        paster = Paster(pasteboard: pasteboard, blobs: blobs)
    }

    deinit {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: root)
    }

    @Test func inlineTextGoesBackOnThePasteboard() throws {
        let record = ClipRecord.text("hello") { _ in "" }
        _ = try paster.copy(record)

        #expect(pasteboard.string(forType: .string) == "hello")
    }

    @Test func blobBackedTextIsReadBackInFull() throws {
        let long = String(repeating: "x", count: ClipRecord.inlineByteLimit + 10)
        let record = try ClipRecord.text(long) { try blobs.write($0) }
        _ = try paster.copy(record)

        #expect(pasteboard.string(forType: .string) == long)
    }

    /// The round trip that used to lose formatting: what was copied out of a rich
    /// editor goes back with every representation it arrived with.
    @Test func richTextSurvivesTheRoundTrip() throws {
        let rtf = Data("{\\rtf1 bold}".utf8)
        let html = Data("<b>bold</b>".utf8)
        let record = try ClipRecord.text(
            "bold",
            rtfKey: try blobs.write(rtf),
            htmlKey: try blobs.write(html)
        ) { try blobs.write($0) }

        _ = try paster.copy(record)

        #expect(pasteboard.data(forType: .rtf) == rtf)
        #expect(pasteboard.data(forType: .html) == html)
        #expect(pasteboard.string(forType: .string) == "bold")
    }

    /// Receiving apps take the first type they understand, so RTF has to be
    /// offered before plain text or nothing ever pastes with formatting.
    @Test func richerFormatsAreOfferedFirst() throws {
        let record = try ClipRecord.text(
            "bold",
            rtfKey: try blobs.write(Data("{\\rtf1 bold}".utf8))
        ) { try blobs.write($0) }

        let types = try paster.snapshot(for: record).representations.map(\.type)
        #expect(types == [
            NSPasteboard.PasteboardType.rtf.rawValue,
            NSPasteboard.PasteboardType.string.rawValue,
        ])
    }

    @Test func imagesGoBackAsImages() throws {
        let png = Fixtures.pngData(width: 12, height: 8)
        let key = try blobs.write(png)
        let record = ClipRecord.image(
            blobKey: key,
            thumbKey: nil,
            contentHash: key,
            byteSize: png.count,
            pixelWidth: 12,
            pixelHeight: 8
        )

        _ = try paster.copy(record)
        #expect(pasteboard.data(forType: .png) == png)
    }

    /// A row can outlive its blob — a crash between the two writes, or a sweep
    /// that ran on a database that failed to open. Better a clear error than a
    /// pasteboard silently cleared of whatever was on it.
    @Test func aClipWhoseBlobIsGoneReportsItRatherThanPastingNothing() {
        let record = ClipRecord.image(
            blobKey: ContentHash.hex(of: "never written"),
            thumbKey: nil,
            contentHash: ContentHash.hex(of: "never written"),
            byteSize: 10,
            pixelWidth: 1,
            pixelHeight: 1
        )

        #expect(throws: PasteError.contentUnavailable) {
            _ = try paster.copy(record)
        }
    }

    /// The number handed to the monitor so it does not record our own paste.
    @Test func copyingReportsTheChangeCountItProduced() throws {
        let before = pasteboard.changeCount
        let after = try paster.copy(ClipRecord.text("hello") { _ in "" })

        #expect(after > before)
        #expect(after == pasteboard.changeCount)
    }
}
