import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Copas

final class ThumbnailStoreTests {

    let root: URL
    let store: ThumbnailStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("copas-thumbs-\(UUID().uuidString)", isDirectory: true)
        store = ThumbnailStore(root: root, maximumPixelSize: 128)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    @Test func thumbnailsAreDownscaledToTheLongestEdge() throws {
        let data = Self.pngData(width: 900, height: 300, opaque: true)
        let key = ContentHash.hex(of: data)
        let thumbKey = try store.makeThumbnail(from: data, key: key)

        let thumbnail = try Data(contentsOf: store.url(for: thumbKey))
        let size = try #require(ThumbnailStore.pixelSize(of: thumbnail))

        #expect(max(size.width, size.height) == 128)
        // 3:1 in, 3:1 out — the transform option must not squash it to a square.
        #expect(size.width == 128 && size.height == 43)
    }

    /// Cards draw thumbnails over a checkerboard so transparency reads as
    /// transparency. JPEG would flatten it, so images with alpha stay PNG.
    @Test func transparencySurvivesAsPNG() throws {
        let data = Self.pngData(width: 200, height: 200, opaque: false)
        let key = ContentHash.hex(of: data)
        let thumbKey = try store.makeThumbnail(from: data, key: key)

        #expect(thumbKey.hasSuffix(".png"))
        #expect(thumbKey.hasPrefix(key))
    }

    @Test func opaqueImagesTakeTheSmallerEncoding() throws {
        let data = Self.pngData(width: 200, height: 200, opaque: true)
        let thumbKey = try store.makeThumbnail(from: data, key: ContentHash.hex(of: data))
        #expect(thumbKey.hasSuffix(".jpg"))
    }

    @Test func nonImageDataIsRejectedRatherThanStored() {
        let data = Data("this is not a picture".utf8)
        #expect(throws: ThumbnailStoreError.notAnImage) {
            _ = try store.makeThumbnail(from: data, key: ContentHash.hex(of: data))
        }
    }

    /// Dimensions come from the header. Decoding a 12 MP screenshot to print two
    /// numbers in a card footer is the kind of cost that only shows up as jank.
    @Test func pixelSizeIsReadWithoutDecoding() throws {
        let data = Self.pngData(width: 640, height: 480, opaque: true)
        let size = try #require(ThumbnailStore.pixelSize(of: data))
        #expect(size == CGSize(width: 640, height: 480))
        #expect(ThumbnailStore.pixelSize(of: Data("nope".utf8)) == nil)
    }

    /// `cached` is called from `body`, so it must answer immediately — including
    /// when the answer is "there is nothing here".
    @Test func cachedReturnsNilForAThumbnailThatWasNeverMade() {
        #expect(store.cached(ContentHash.hex(of: "absent") + ".jpg") == nil)
    }

    @Test func cachedReadsFromDiskAndThenFromMemory() throws {
        let data = Self.pngData(width: 200, height: 200, opaque: true)
        let thumbKey = try store.makeThumbnail(from: data, key: ContentHash.hex(of: data))

        #expect(store.cached(thumbKey) != nil)

        // Remove the file: a second hit must come from the cache, not the disk.
        try FileManager.default.removeItem(at: store.url(for: thumbKey))
        #expect(store.cached(thumbKey) != nil)
    }

    @Test func garbageCollectionRemovesOrphanedThumbnails() throws {
        let kept = try store.makeThumbnail(from: Self.pngData(width: 40, height: 40, opaque: true),
                                           key: ContentHash.hex(of: "kept"))
        let orphan = try store.makeThumbnail(from: Self.pngData(width: 60, height: 60, opaque: true),
                                             key: ContentHash.hex(of: "orphan"))

        #expect(try store.collectGarbage(keeping: [kept]) == 1)
        #expect(store.contains(kept))
        #expect(!store.contains(orphan))
    }

    // MARK: - Fixtures

    /// A solid rectangle, or a half-transparent one, encoded as PNG.
    static func pngData(width: Int, height: Int, opaque: Bool) -> Data {
        let alphaInfo: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: alphaInfo.rawValue
        )!

        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: opaque ? 1 : 0.5))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let image = context.makeImage()!
        let encoded = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            encoded as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        )!
        CGImageDestinationAddImage(destination, image, nil)
        _ = CGImageDestinationFinalize(destination)
        return encoded as Data
    }
}
