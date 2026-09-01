import Foundation

enum BlobStoreError: Error, Equatable {
    /// A key that is not a SHA-256 hex digest. Refused rather than resolved,
    /// because a key is a path component and imported data is not ours.
    case invalidKey(String)
    case missing(String)
}

/// Clip content too large to sit in a row: images always, text over 8 KB.
///
/// The key *is* the SHA-256 of the bytes, which is the same value the `clip` row
/// stores as its dedupe hash. One number does both jobs, so a row and its file
/// can never disagree about which content they mean.
struct BlobStore: Sendable {

    private let directory: ContentAddressedDirectory

    init(root: URL) {
        self.directory = ContentAddressedDirectory(root: root)
    }

    var root: URL { directory.root }

    /// Stores the data and returns its key. Storing the same bytes twice is free.
    @discardableResult
    func write(_ data: Data) throws -> String {
        let key = ContentHash.hex(of: data)
        try directory.write(data, filename: key)
        return key
    }

    func contains(_ key: String) -> Bool {
        ContentHash.isValidKey(key) && directory.contains(key)
    }

    func data(for key: String) throws -> Data {
        try validate(key)
        guard directory.contains(key) else { throw BlobStoreError.missing(key) }
        return try directory.data(for: key)
    }

    func url(for key: String) throws -> URL {
        try validate(key)
        return directory.url(for: key)
    }

    /// Deletes orphans. See ``ContentAddressedDirectory/collectGarbage(keeping:)``
    /// for why this is a sweep and not part of deleting a clip.
    @discardableResult
    func collectGarbage(keeping live: Set<String>) throws -> Int {
        try directory.collectGarbage(keeping: live)
    }

    private func validate(_ key: String) throws {
        guard ContentHash.isValidKey(key) else { throw BlobStoreError.invalidKey(key) }
    }
}
