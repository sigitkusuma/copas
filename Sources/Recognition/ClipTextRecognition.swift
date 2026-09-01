import CoreGraphics
import Foundation
import ImageIO

/// Reads the text out of stored image clips and files it against the row.
///
/// Runs on every image as it arrives, in the background. That is what turns
/// recognised text from a thing you can ask for into a thing that is simply
/// there — `has:text` finds screenshots, a search matches words inside a
/// picture, and the badge on a card means something. Recognition is local and
/// costs a few hundred milliseconds off the main thread, once per image copied.
struct ClipTextRecognition: Sendable {

    let clips: ClipRepository
    let blobs: BlobStore

    func recognize(_ record: ClipRecord) async {
        guard record.kind == .image, let key = record.blobKey else { return }
        guard let image = Self.decode(try? blobs.data(for: key)) else { return }

        guard
            let recognized = await TextRecognizer.recognizeText(in: image),
            case let trimmed = recognized.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return }

        do {
            _ = try clips.setRecognizedText(trimmed, for: record.id)
        } catch {
            // The clip is perfectly usable without its text; only search is poorer.
            Log.store.error("could not store recognised text: \(error, privacy: .public)")
        }
    }

    /// Through ImageIO rather than `NSImage`, so this stays off the main actor.
    static func decode(_ data: Data?) -> CGImage? {
        guard
            let data,
            let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
