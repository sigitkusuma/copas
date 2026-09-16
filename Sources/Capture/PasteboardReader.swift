import AppKit
import Foundation
import UniformTypeIdentifiers

/// Turns the contents of a pasteboard into a ``CapturedPayload``.
///
/// Split out from ``PasteboardMonitor`` so it can be pointed at a private
/// `NSPasteboard(name:)` in tests — the reading rules are the fiddly part, and
/// they are the part worth testing without waiting on a poll timer.
@MainActor
struct PasteboardReader {

    /// Image files larger than this are left alone. Reading one happens on the
    /// main thread, and while that is once per copy rather than once per poll,
    /// there is no size at which stalling the UI to swallow a file is the right
    /// trade.
    var maximumImageFileBytes = 32 * 1024 * 1024

    var excludedBundleIDs: Set<String> = []

    func read(
        _ pasteboard: NSPasteboard,
        source: SourceApp,
        at date: Date = Date()
    ) -> CapturedPayload? {
        let types = (pasteboard.types ?? []).map(\.rawValue)

        guard !PasteboardPrivacy.shouldIgnore(
            types: types,
            sourceBundleID: source.bundleID,
            excludedBundleIDs: excludedBundleIDs
        ) else { return nil }

        let payload: (CapturedPayload.Content)? =
            imageFileContent(from: pasteboard)
            ?? imageContent(from: pasteboard)
            ?? textContent(from: pasteboard)

        guard let payload else { return nil }

        let captured = CapturedPayload(
            content: payload,
            source: source,
            capturedAt: date,
            changeCount: pasteboard.changeCount
        )
        return captured.isEmpty ? nil : captured
    }

    // MARK: - Readers, in priority order

    /// A single image file, as Finder writes it.
    ///
    /// Checked before text because Finder puts the file's *path* on the
    /// pasteboard as a string alongside the file reference. Read the string
    /// first and copying a screenshot out of Finder silently stores the words
    /// `/Users/…/Screenshot.png` instead of the picture.
    private func imageFileContent(from pasteboard: NSPasteboard) -> CapturedPayload.Content? {
        guard
            let urls = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL],
            urls.count == 1,
            let url = urls.first,
            let type = UTType(filenameExtension: url.pathExtension.lowercased()),
            type.conforms(to: .image)
        else { return nil }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0, size <= maximumImageFileBytes else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return .image(normalizeToPNG(data))
    }

    /// Image bytes written directly, as web browsers, Preview or screenshot tools do.
    ///
    /// Checked before text because browsers (Safari, Chrome, etc.) write image data
    /// alongside plain text URLs or alt strings. Checking text first causes web images
    /// to be stored as URL strings rather than actual pictures.
    ///
    /// PNG is preferred and taken as-is; other formats are re-encoded to PNG so that
    /// the same picture always hashes to the same value no matter which format the
    /// source app happened to offer.
    private func imageContent(from pasteboard: NSPasteboard) -> CapturedPayload.Content? {
        if let png = pasteboard.data(forType: .png), !png.isEmpty {
            return .image(png)
        }
        if let tiff = pasteboard.data(forType: .tiff), !tiff.isEmpty {
            return .image(normalizeToPNG(tiff))
        }

        let supportedImageTypes: [NSPasteboard.PasteboardType] = [
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("public.image"),
            .init("image/png"),
            .init("image/jpeg")
        ]
        for type in supportedImageTypes {
            if let data = pasteboard.data(forType: type), !data.isEmpty {
                return .image(normalizeToPNG(data))
            }
        }

        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil),
           let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let first = images.first,
           let tiff = first.tiffRepresentation {
            return .image(normalizeToPNG(tiff))
        }

        return nil
    }

    /// Text, with every richer format the source app offered.
    private func textContent(from pasteboard: NSPasteboard) -> CapturedPayload.Content? {
        guard let plain = pasteboard.string(forType: .string), !plain.isEmpty else { return nil }
        return .text(RichText(
            plain: plain,
            rtf: pasteboard.data(forType: .rtf),
            html: pasteboard.data(forType: .html)
        ))
    }

    private func normalizeToPNG(_ data: Data) -> Data {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return data
        }
        if let bitmap = NSBitmapImageRep(data: data),
           let png = bitmap.representation(using: .png, properties: [:]) {
            return png
        }
        return data
    }

    /// The app the copy came from, as far as the system will say.
    static func frontmostApp() -> SourceApp {
        guard let app = NSWorkspace.shared.frontmostApplication else { return SourceApp() }
        return SourceApp(bundleID: app.bundleIdentifier, name: app.localizedName)
    }
}
