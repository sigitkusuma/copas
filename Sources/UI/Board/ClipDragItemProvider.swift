import AppKit
import Foundation
import UniformTypeIdentifiers

/// Prepares pasteboard item providers for dragging clips out of Copas into any macOS app.
///
/// For images: writes a temporary `.png` file so Finder and file-centric apps receive
/// a legitimate file drop, alongside in-memory PNG/TIFF data representations and NSImage
/// for graphics and chat applications.
enum ClipDragItemProvider {

    /// Returns an item provider configured with file URL, data, and image representations.
    static func itemProvider(forImageData data: Data, id: String) -> NSItemProvider {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopasDrags", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let shortID = String(id.prefix(8))
        let filename = "Copas-\(shortID).png"
        let fileURL = tempDir.appendingPathComponent(filename)
        try? data.write(to: fileURL)

        // Initialize from file URL so Finder, Desktop, Mail, and file drop targets
        // receive a genuine file-backed item provider (public.file-url, public.url, public.png).
        let provider = NSItemProvider(contentsOf: fileURL) ?? NSItemProvider()
        provider.suggestedName = "Copas-\(shortID)"

        // 1. Explicit NSURL object representation — Finder and file drop targets
        provider.registerObject(fileURL as NSURL, visibility: .all)

        // 2. Direct TIFF representation — for legacy graphics apps
        if let bitmap = NSBitmapImageRep(data: data), let tiff = bitmap.tiffRepresentation {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.tiff.identifier,
                visibility: .all
            ) { completion in
                completion(tiff, nil)
                return nil
            }
        }

        // 3. NSImage object representation — for drag image preview and AppKit targets
        if let image = NSImage(data: data) {
            provider.registerObject(image, visibility: .all)
        }

        return provider
    }

    /// Returns an item provider for dragging plain text clips.
    static func itemProvider(forText text: String) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerObject(text as NSString, visibility: .all)
        return provider
    }
}
