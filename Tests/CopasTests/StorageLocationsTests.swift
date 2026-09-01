import Foundation
import GRDB
import Testing

@testable import Copas

/// Exercises the real on-disk path. Everything else in this suite runs against
/// an in-memory database, which cannot catch a file written to the wrong place.
final class StorageLocationsTests {

    let root: URL
    let locations: StorageLocations

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("copas-support-\(UUID().uuidString)", isDirectory: true)
        locations = StorageLocations(root: root)
        try locations.createDirectories()
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// The previous app keeps running out of this same directory until its owner
    /// decides otherwise. Writing over `history.json` would take their history
    /// with it.
    @Test func openingTheDatabaseLeavesThePreviousAppsFilesAlone() throws {
        let history = Data(#"[{"id":"legacy"}]"#.utf8)
        try history.write(to: locations.legacyHistoryFile)
        try FileManager.default.createDirectory(at: locations.legacyTextsDirectory,
                                                withIntermediateDirectories: true)

        let database = try AppDatabase.onDisk(at: locations)
        let repository = ClipRepository(database: database)
        _ = try repository.insert(ClipRecord.text("hello") { _ in "" })

        #expect(try Data(contentsOf: locations.legacyHistoryFile) == history)
        #expect(FileManager.default.fileExists(atPath: locations.legacyTextsDirectory.path))
        #expect(FileManager.default.fileExists(atPath: locations.databaseFile.path))
        #expect(FileManager.default.fileExists(atPath: locations.blobsDirectory.path))
        #expect(FileManager.default.fileExists(atPath: locations.thumbnailsDirectory.path))
    }

    /// The point of a cryptographic content hash: dedupe still works after a
    /// relaunch. A per-process `hashValue` would compare unequal here and quietly
    /// store a second copy.
    @Test func historySurvivesReopeningAndStillDeduplicates() throws {
        let clip = ClipRecord.text("persist me") { _ in "" }

        do {
            let repository = ClipRepository(database: try AppDatabase.onDisk(at: locations))
            _ = try repository.insert(clip)
        }

        let reopened = ClipRepository(database: try AppDatabase.onDisk(at: locations))
        #expect(try reopened.count() == 1)

        let again = try reopened.insert(ClipRecord.text("persist me") { _ in "" })
        #expect(!again.isNew)
        #expect(again.record.id == clip.id)
        #expect(try reopened.count() == 1)
    }

    @Test func theDatabaseUsesWriteAheadLogging() throws {
        let database = try AppDatabase.onDisk(at: locations)
        let mode = try database.writer.read { db in
            try String.fetchOne(db, sql: "PRAGMA journal_mode")
        }
        #expect(mode == "wal")
    }
}
