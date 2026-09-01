import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ThumbnailStoreError: Error, Equatable {
    case notAnImage
    case encodingFailed
    case invalidKey(String)
}

/// Small, ready-to-draw copies of image clips.
///
/// Two things make a card strip scroll smoothly, and both are here. Thumbnails
/// are generated **once, at capture**, by ImageIO — `CGImageSourceCreateThumbnailAtIndex`
/// reads only as much of the file as the smaller size needs, so a 12 MP
/// screenshot never gets decoded to a full bitmap. And ``cached(_:)`` answers
/// **synchronously** from an `NSCache`, so a warm strip does no asynchronous work
/// at all while scrolling — the progress spinner is for the cold path only, which
/// is exactly the distinction the app this replaces failed to make.
final class ThumbnailStore: @unchecked Sendable {

    /// `NSCache` is documented thread-safe and the other two properties are
    /// immutable, so the unchecked conformance covers exactly one thing:
    /// `NSCache` predates `Sendable` annotation.
    private let cache = NSCache<NSString, NSImage>()
    private let directory: ContentAddressedDirectory

    /// Longest edge, in pixels. Twice the card's width so it stays sharp on a
    /// Retina display without storing a second full-resolution copy.
    let maximumPixelSize: Int

    init(root: URL, maximumPixelSize: Int) {
        self.directory = ContentAddressedDirectory(root: root)
        self.maximumPixelSize = maximumPixelSize
        cache.countLimit = 400
    }

    var root: URL { directory.root }

    // MARK: - Generating

    /// Renders and stores a thumbnail for image data already in the blob store.
    ///
    /// - Parameter key: the blob's SHA-256, so the thumbnail is addressed by the
    ///   same value as the thing it depicts.
    /// - Returns: the thumbnail key, which is the blob key plus a file extension.
    @discardableResult
    func makeThumbnail(from data: Data, key: String) throws -> String {
        guard ContentHash.isValidKey(key) else { throw ThumbnailStoreError.invalidKey(key) }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ThumbnailStoreError.notAnImage
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ThumbnailStoreError.notAnImage
        }

        // Transparency has to survive: cards draw thumbnails over a checkerboard
        // so an image with alpha reads as transparent rather than as white. JPEG
        // would flatten that, so anything with an alpha channel is kept as PNG and
        // only opaque images take the smaller encoding.
        let hasAlpha: Bool
        switch thumbnail.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            hasAlpha = false
        default:
            hasAlpha = true
        }

        let type = hasAlpha ? UTType.png : UTType.jpeg
        let filename = key + (hasAlpha ? ".png" : ".jpg")

        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded as CFMutableData,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw ThumbnailStoreError.encodingFailed
        }
        CGImageDestinationAddImage(destination, thumbnail, [
            kCGImageDestinationLossyCompressionQuality: 0.8
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ThumbnailStoreError.encodingFailed
        }

        try directory.write(encoded as Data, filename: filename)
        return filename
    }

    /// The pixel dimensions of image data, read from its header alone.
    ///
    /// Never decodes the image. Card footers show `W × H`, and doing this the
    /// obvious way — `NSImage(data:).size` — would decode every clip on capture
    /// just to print two numbers.
    static func pixelSize(of data: Data) -> CGSize? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }

    // MARK: - Reading

    /// A thumbnail, from memory or from disk, without ever suspending.
    ///
    /// Safe to call from `body`. Returns `nil` when the file is genuinely absent,
    /// which is the caller's cue to draw a placeholder rather than to go looking.
    func cached(_ key: String) -> NSImage? {
        let cacheKey = key as NSString
        if let hit = cache.object(forKey: cacheKey) { return hit }
        guard directory.contains(key),
              let data = try? directory.data(for: key),
              let image = NSImage(data: data)
        else { return nil }
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    func contains(_ key: String) -> Bool {
        directory.contains(key)
    }

    func url(for key: String) -> URL {
        directory.url(for: key)
    }

    @discardableResult
    func collectGarbage(keeping live: Set<String>) throws -> Int {
        let removed = try directory.collectGarbage(keeping: live)
        if removed > 0 { cache.removeAllObjects() }
        return removed
    }
}
