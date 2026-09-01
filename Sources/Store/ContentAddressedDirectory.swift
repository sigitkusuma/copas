import Foundation

/// A directory of files named after their own content, one shard level deep.
///
/// Files go in `<root>/<first two hex characters>/<filename>`. The shard exists
/// because a flat directory holding tens of thousands of entries makes every
/// directory read — ours and Finder's — proportionally slower, while 256 buckets
/// keeps each one small for any history a person will actually accumulate.
///
/// Content addressing means a write is idempotent and two identical clips share
/// one file, which in turn is why deletion is a sweep rather than an unlink:
/// nothing here knows how many rows point at a given file.
struct ContentAddressedDirectory: Sendable {

    let root: URL

    init(root: URL) {
        self.root = root
    }

    func url(for filename: String) -> URL {
        root
            .appendingPathComponent(String(filename.prefix(2)), isDirectory: true)
            .appendingPathComponent(filename)
    }

    func contains(_ filename: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: filename).path)
    }

    /// Writes unless the file is already there. Identical content is identical
    /// bytes, so rewriting it would only risk truncating a file something else is
    /// mid-read.
    func write(_ data: Data, filename: String) throws {
        let destination = url(for: filename)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
    }

    func data(for filename: String) throws -> Data {
        try Data(contentsOf: url(for: filename))
    }

    func remove(_ filename: String) throws {
        let target = url(for: filename)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }

    /// Every filename currently on disk.
    func filenames() throws -> Set<String> {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        var found: Set<String> = []
        for shard in try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            let isDirectory = (try? shard.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
            guard isDirectory == true else { continue }
            let contents = try fileManager.contentsOfDirectory(
                at: shard,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            found.formUnion(contents.map(\.lastPathComponent))
        }
        return found
    }

    /// Deletes anything no row references any more, and returns how many went.
    ///
    /// Run at launch, not at delete time. A file left behind by a crash costs
    /// disk until the next launch; a file unlinked while another clip still shows
    /// it is a clip that renders as a blank card forever. Sweeping repairs both.
    @discardableResult
    func collectGarbage(keeping live: Set<String>) throws -> Int {
        var removed = 0
        for filename in try filenames() where !live.contains(filename) {
            try remove(filename)
            removed += 1
        }
        try removeEmptyShards()
        return removed
    }

    private func removeEmptyShards() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else { return }
        for shard in try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            let contents = try? fileManager.contentsOfDirectory(atPath: shard.path)
            if contents?.isEmpty == true {
                try? fileManager.removeItem(at: shard)
            }
        }
    }
}
