import Foundation

/// Every on-disk path the app owns, resolved once and passed down.
///
/// The application-support directory is shared with the clipboard manager this
/// app replaces: `history.json`, `texts/` and `images/` are its files. They are
/// read exactly once, by `LegacyCopasImporter`, and never written or deleted —
/// the old app has to keep working until its owner chooses to remove it. Our own
/// state is `clips.sqlite`, `blobs/` and `thumbs/`, none of which it knows about.
struct StorageLocations: Sendable, Equatable {

    /// `~/Library/Application Support/Copas`
    let root: URL

    init(root: URL) {
        self.root = root
    }

    /// The real location for a running app.
    static func standard(fileManager: FileManager = .default) throws -> StorageLocations {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return StorageLocations(root: support.appendingPathComponent("Copas", isDirectory: true))
    }

    // MARK: - Ours

    var databaseFile: URL { root.appendingPathComponent("clips.sqlite") }
    var blobsDirectory: URL { root.appendingPathComponent("blobs", isDirectory: true) }
    var thumbnailsDirectory: URL { root.appendingPathComponent("thumbs", isDirectory: true) }

    // MARK: - The previous app's, read-only

    var legacyHistoryFile: URL { root.appendingPathComponent("history.json") }
    var legacyTextsDirectory: URL { root.appendingPathComponent("texts", isDirectory: true) }
    var legacyImagesDirectory: URL { root.appendingPathComponent("images", isDirectory: true) }

    /// Creates the directories we write into. Safe to call on every launch.
    func createDirectories(fileManager: FileManager = .default) throws {
        for directory in [root, blobsDirectory, thumbnailsDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
