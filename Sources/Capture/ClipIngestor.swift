import Foundation

/// Turns a captured payload into a stored clip.
///
/// The seam between AppKit and the database: ``PasteboardMonitor`` knows nothing
/// about storage, ``ClipRepository`` knows nothing about pasteboards, and this
/// is the only thing that knows both. It is `Sendable` and does real work —
/// hashing, encoding, file writes — so it runs off the main thread while the
/// monitor stays on it.
struct ClipIngestor: Sendable {

    let clips: ClipRepository
    let blobs: BlobStore
    let thumbnails: ThumbnailStore

    init(clips: ClipRepository, blobs: BlobStore, thumbnails: ThumbnailStore) {
        self.clips = clips
        self.blobs = blobs
        self.thumbnails = thumbnails
    }

    /// Returns `nil` for a payload with nothing worth keeping — empty text, or
    /// bytes that turn out not to be a decodable image.
    @discardableResult
    func ingest(_ payload: CapturedPayload) throws -> InsertOutcome? {
        switch payload.content {
        case .text(let rich):
            return try ingest(rich, from: payload)
        case .image(let data):
            return try ingest(image: data, from: payload)
        }
    }

    private func ingest(_ rich: RichText, from payload: CapturedPayload) throws -> InsertOutcome? {
        guard !rich.isEmpty else { return nil }

        // Written before the row, and before knowing whether this is a duplicate.
        // Content-addressed writes of bytes already on disk are a no-op, so the
        // repeat costs a hash rather than a file.
        let rtfKey = try rich.rtf.map { try blobs.write($0) }
        let htmlKey = try rich.html.map { try blobs.write($0) }

        let record = try ClipRecord.text(
            rich.plain,
            source: payload.source,
            at: payload.capturedAt,
            rtfKey: rtfKey,
            htmlKey: htmlKey,
            overflow: { try blobs.write($0) }
        )
        return try clips.insert(record)
    }

    private func ingest(image data: Data, from payload: CapturedPayload) throws -> InsertOutcome? {
        // Read from the header, so nothing here decodes a screenshot. Also the
        // test for "is this actually an image": bytes ImageIO cannot describe are
        // not something a card could ever draw.
        guard let size = ThumbnailStore.pixelSize(of: data) else { return nil }

        let blobKey = try blobs.write(data)
        // A missing thumbnail costs a placeholder on one card. It is not worth
        // discarding the clip over, so the failure is swallowed deliberately.
        let thumbKey = try? thumbnails.makeThumbnail(from: data, key: blobKey)

        let record = ClipRecord.image(
            blobKey: blobKey,
            thumbKey: thumbKey,
            contentHash: blobKey,
            byteSize: data.count,
            pixelWidth: Int(size.width),
            pixelHeight: Int(size.height),
            source: payload.source,
            at: payload.capturedAt
        )
        return try clips.insert(record)
    }
}
