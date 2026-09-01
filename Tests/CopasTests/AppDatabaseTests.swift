import Foundation
import GRDB
import Testing

@testable import Copas

struct AppDatabaseTests {

    @Test func migrationRunsCleanOnAnEmptyDatabase() throws {
        let database = try AppDatabase.inMemory()
        let (hasClips, hasIndex) = try database.writer.read { db in
            (try db.tableExists("clip"), try db.tableExists("clip_fts"))
        }
        #expect(hasClips)
        #expect(hasIndex)
    }

    /// `synchronize(withTable:)` is what keeps the index honest. If these
    /// triggers ever stop being created, clips would still store fine and simply
    /// never turn up in search — a failure with no symptom until someone looks
    /// for something they know is there.
    @Test func theFullTextIndexIsKeptInStepByTriggers() throws {
        let database = try AppDatabase.inMemory()
        let triggers = try database.writer.read { db in
            try String.fetchSet(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'trigger'"
            )
        }
        #expect(triggers.count == 3, "expected insert, update and delete triggers, got \(triggers.sorted())")
    }

    @Test func migratingTwiceChangesNothing() throws {
        let queue = try DatabaseQueue(path: ":memory:", configuration: AppDatabase.configuration)
        _ = try AppDatabase(queue)
        _ = try AppDatabase(queue)
        let hasClips = try queue.read { db in try db.tableExists("clip") }
        #expect(hasClips)
    }

    @Test func contentHashIsUniqueAtTheSchemaLevel() throws {
        let database = try AppDatabase.inMemory()
        let first = ClipRecord.text("same", id: "a") { _ in "" }
        let second = ClipRecord.text("same", id: "b") { _ in "" }

        try database.writer.write { db in try first.insert(db) }

        // Not routed through ClipRepository on purpose: this asserts the database
        // itself refuses duplicates, so a second write path cannot reintroduce them.
        #expect(throws: DatabaseError.self) {
            try database.writer.write { db in try second.insert(db) }
        }
    }
}
