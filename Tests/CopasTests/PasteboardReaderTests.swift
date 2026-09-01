import AppKit
import Foundation
import Testing

@testable import Copas

@MainActor
final class PasteboardReaderTests {

    let pasteboard = Fixtures.pasteboard()
    let reader = PasteboardReader()
    let source = SourceApp(bundleID: "com.apple.TextEdit", name: "TextEdit")

    deinit {
        pasteboard.releaseGlobally()
    }

    @Test func plainTextIsRead() {
        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)

        let payload = reader.read(pasteboard, source: source)
        #expect(payload?.content == .text(RichText(plain: "hello")))
        #expect(payload?.source == source)
    }

    /// The formatting fix: a rich editor offers three representations at once and
    /// all three are kept, so a round trip through the clipboard is lossless.
    @Test func richerFormatsAreKeptAlongsideThePlainText() {
        let rtf = Data("{\\rtf1 bold}".utf8)
        let html = Data("<b>bold</b>".utf8)

        pasteboard.clearContents()
        pasteboard.setData(rtf, forType: .rtf)
        pasteboard.setData(html, forType: .html)
        pasteboard.setString("bold", forType: .string)

        guard case .text(let text)? = reader.read(pasteboard, source: source)?.content else {
            Issue.record("expected text")
            return
        }
        #expect(text.plain == "bold")
        #expect(text.rtf == rtf)
        #expect(text.html == html)
        #expect(text.hasAlternates)
    }

    @Test func concealedContentIsNeverRead() {
        pasteboard.clearContents()
        pasteboard.setString("hunter2", forType: .string)
        pasteboard.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))

        #expect(reader.read(pasteboard, source: source) == nil)
    }

    @Test func emptyTextIsNotAClip() {
        pasteboard.clearContents()
        pasteboard.setString("", forType: .string)
        #expect(reader.read(pasteboard, source: source) == nil)
    }

    @Test func imageBytesAreRead() {
        let png = Fixtures.pngData(width: 20, height: 10)
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)

        #expect(reader.read(pasteboard, source: source)?.content == .image(png))
    }

    /// TIFF is re-encoded so the same picture hashes the same way whichever
    /// format the source app happened to offer — otherwise dedupe misses.
    @Test func tiffIsNormalisedToPNG() {
        pasteboard.clearContents()
        pasteboard.setData(Fixtures.tiffData(width: 20, height: 10), forType: .tiff)

        guard case .image(let data)? = reader.read(pasteboard, source: source)?.content else {
            Issue.record("expected an image")
            return
        }
        #expect(ThumbnailStore.pixelSize(of: data) == CGSize(width: 20, height: 10))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]), "expected a PNG signature")
    }

    /// Finder writes the file's *path* as a string next to the file reference.
    /// Read the string first and copying a screenshot stores the words
    /// "/Users/…/Screenshot.png" instead of the picture.
    @Test func aCopiedImageFileBeatsThePathStringFinderWritesBesideIt() throws {
        let directory = try Fixtures.temporaryDirectory("reader")
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("Screenshot.png")
        let png = Fixtures.pngData(width: 32, height: 16)
        try png.write(to: file)

        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        pasteboard.setString(file.path, forType: .string)

        #expect(reader.read(pasteboard, source: source)?.content == .image(png))
    }

    @Test func aCopiedTextFileFallsBackToItsPath() throws {
        let directory = try Fixtures.temporaryDirectory("reader")
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("notes.txt")
        try Data("not an image".utf8).write(to: file)

        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        pasteboard.setString(file.path, forType: .string)

        #expect(reader.read(pasteboard, source: source)?.content == .text(RichText(plain: file.path)))
    }

    /// Reading a file happens on the main thread. There is no size at which
    /// stalling the UI to swallow one is the right trade.
    @Test func anOversizedImageFileIsLeftAlone() throws {
        let directory = try Fixtures.temporaryDirectory("reader")
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("huge.png")
        try Fixtures.pngData(width: 64, height: 64).write(to: file)

        var small = reader
        small.maximumImageFileBytes = 16

        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        pasteboard.setString(file.path, forType: .string)

        #expect(small.read(pasteboard, source: source)?.content == .text(RichText(plain: file.path)))
    }
}
