import Foundation
import GRDB

/// Owns the database connection and the schema.
///
/// Nothing else in the app opens a connection or writes DDL. Splitting this from
/// ``ClipRepository`` keeps "how do we connect and what shape is the schema"
/// separate from "what questions do we ask", which is what makes the repository
/// testable against an in-memory database that no file ever backs.
final class AppDatabase: Sendable {

    let writer: any DatabaseWriter

    /// Migrates on the way in, so no caller can ever hold a connection whose
    /// schema is behind the code that queries it.
    init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// The real database, alongside the previous app's files but sharing nothing
    /// with them. See ``StorageLocations``.
    static func onDisk(at locations: StorageLocations) throws -> AppDatabase {
        try locations.createDirectories()
        let queue = try DatabaseQueue(
            path: locations.databaseFile.path,
            configuration: configuration
        )
        return try AppDatabase(queue)
    }

    /// A throwaway database for tests.
    static func inMemory() throws -> AppDatabase {
        try AppDatabase(try DatabaseQueue(path: ":memory:", configuration: configuration))
    }

    static var configuration: Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in
            // Write-ahead logging suits the access pattern: one small insert per
            // copy, arriving at whatever rate the user works, against reads that
            // must not block behind them. In-memory databases ignore this and
            // report "memory" rather than failing.
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        return configuration
    }

    // MARK: - Schema

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // `eraseDatabaseOnSchemaChange` is deliberately left off, even in DEBUG.
        // It is the conventional development setting, but this app becomes the
        // machine's real clipboard history early — a migration edited in place
        // would then wipe it without a word. Migrations are append-only instead,
        // and a stale development database gets deleted by hand.

        migrator.registerMigration("v1.clips") { db in
            try db.create(table: "clip") { t in
                t.column("id", .text).primaryKey()
                t.column("kind", .integer).notNull()
                t.column("created_at", .double).notNull()
                t.column("source_bundle_id", .text)
                t.column("source_app_name", .text)
                t.column("preview", .text).notNull().defaults(to: "")
                t.column("content_hash", .text).notNull()
                t.column("byte_size", .integer).notNull().defaults(to: 0)
                t.column("char_count", .integer).notNull().defaults(to: 0)
                t.column("is_inline", .boolean).notNull().defaults(to: false)
                t.column("inline_text", .text)
                t.column("blob_key", .text)
                t.column("thumb_key", .text)
                t.column("pixel_width", .integer)
                t.column("pixel_height", .integer)
                t.column("recognized_text", .text)
                t.column("recognized_at", .double)
                t.column("legacy_flags", .text)
            }

            // Every listing is newest-first and pages on (created_at, id), so the
            // index carries both — otherwise the tiebreaker forces a sort.
            try db.create(
                index: "clip_on_created_at",
                on: "clip",
                columns: ["created_at", "id"]
            )

            // Dedupe is enforced here rather than by convention in the writer.
            // A unique index means a second path into the table cannot quietly
            // reintroduce duplicates.
            try db.create(
                index: "clip_on_content_hash",
                on: "clip",
                columns: ["content_hash"],
                unique: true
            )

            try db.create(
                index: "clip_on_source_bundle_id",
                on: "clip",
                columns: ["source_bundle_id"]
            )

            try db.create(virtualTable: "clip_fts", using: FTS5()) { t in
                // External content: the index stores no copy of the text, and
                // `synchronize` installs the triggers that keep it in step with
                // `clip`. Without it, every write site would have to remember to
                // update the index, and one that forgot would produce a clip that
                // exists but cannot be found.
                t.synchronize(withTable: "clip")
                t.column("preview")
                t.column("recognized_text")
                t.column("source_app_name")
                // Prefix indexes make as-you-type search a lookup rather than a
                // scan. Two and three characters is where typing actually starts
                // returning something worth looking at.
                t.prefixes = [2, 3]
            }
        }

        // Text copied out of a rich editor arrives in several formats at once.
        // Keeping only the plain string means every round trip through the
        // clipboard silently strips formatting, which is what the app this
        // replaces did. Both alternates are blob keys rather than columns:
        // a copied web page's HTML is regularly larger than the text it wraps.
        migrator.registerMigration("v2.richText") { db in
            try db.alter(table: "clip") { t in
                t.add(column: "rtf_key", .text)
                t.add(column: "html_key", .text)
            }
        }

        // Search that only reaches the first 240 characters of a clip is search
        // that fails on exactly the clips worth searching for — the long ones you
        // cannot skim past. Indexing `inline_text` alongside the preview makes
        // everything up to the 8 KB inline limit findable, which is very nearly
        // everything. Text large enough to live in a blob still matches on its
        // preview alone; that is the price of not reading every blob on write.
        migrator.registerMigration("v3.searchWholeClips") { db in
            // The synchronising triggers are named after the table they feed, so
            // they have to go before it can be replaced.
            try db.execute(sql: """
                DROP TRIGGER IF EXISTS __clip_fts_ai;
                DROP TRIGGER IF EXISTS __clip_fts_ad;
                DROP TRIGGER IF EXISTS __clip_fts_au;
                """)
            try db.drop(table: "clip_fts")

            try db.create(virtualTable: "clip_fts", using: FTS5()) { t in
                t.synchronize(withTable: "clip")
                t.column("preview")
                t.column("inline_text")
                t.column("recognized_text")
                t.column("source_app_name")
                t.prefixes = [2, 3]
            }
        }

        return migrator
    }
}
