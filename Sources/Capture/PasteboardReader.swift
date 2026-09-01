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
            ?? textContent(from: pasteboard)
            ?? imageContent(from: pasteboard)

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
        return .image(data)
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

    /// Image bytes written directly, as Preview or a screenshot tool does.
    ///
    /// PNG is preferred and taken as-is; TIFF is re-encoded so that the same
    /// picture always hashes to the same value no matter which format the
    /// source app happened to offer.
    private func imageContent(from pasteboard: NSPasteboard) -> CapturedPayload.Content? {
        if let png = pasteboard.data(forType: .png) { return .image(png) }
        guard let tiff = pasteboard.data(forType: .tiff) else { return nil }
        guard
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else { return .image(tiff) }
        return .image(png)
    }

    /// The app the copy came from, as far as the system will say.
    static func frontmostApp() -> SourceApp {
        guard let app = NSWorkspace.shared.frontmostApplication else { return SourceApp() }
        return SourceApp(bundleID: app.bundleIdentifier, name: app.localizedName)
    }
}
