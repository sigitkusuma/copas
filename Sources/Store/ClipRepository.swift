import Foundation
import GRDB

/// What happened to a clip on the way in.
enum InsertOutcome: Sendable, Equatable {
    /// Content the history had not seen before.
    case inserted(ClipRecord)
    /// Content already present, moved back to the top of the history.
    case promoted(ClipRecord)

    var record: ClipRecord {
        switch self {
        case .inserted(let record), .promoted(let record): return record
        }
    }

    var isNew: Bool {
        if case .inserted = self { return true }
        return false
    }
}

/// The tally a bulk import reports back.
struct ImportSummary: Sendable, Equatable {
    var imported = 0
    /// Already present — by id, or by content. Re-running an import is harmless.
    var skipped = 0
    /// Imported, but with something missing: usually a sidecar file the old app
    /// referenced and no longer has, where all that survives is the preview.
    var degraded = 0
}

/// Every read and write of clip history.
///
/// The single writer, on purpose. The app this replaces spread inserts, deletes,
/// trimming and search across one 405-line store object that also held view
/// state, and the resulting call graph made it genuinely hard to say what could
/// mutate history and when. Here the surface is small enough to read in one go.
///
/// Nothing in this type touches the filesystem. Blobs and thumbnails are keys to
/// it — see ``BlobStore`` and ``ThumbnailStore``.
final class ClipRepository: Sendable {

    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - Writing

    /// Stores a clip, or moves an identical one back to the top.
    ///
    /// Copying the same snippet twice should leave one card, freshly dated, not
    /// two — and it should keep the id the first copy had, so anything holding a
    /// selection does not lose it.
    @discardableResult
    func insert(_ record: ClipRecord) throws -> InsertOutcome {
        try database.writer.write { db in
            if var existing = try ClipRecord
                .filter(ClipRecord.Columns.contentHash == record.contentHash)
                .fetchOne(db)
            {
                existing.createdAt = record.createdAt
                // The source is the *most recent* place this content came from,
                // which is the more useful answer when the same snippet gets
                // copied out of two different apps.
                if record.sourceBundleID != nil || record.sourceAppName != nil {
                    existing.sourceBundleID = record.sourceBundleID
                    existing.sourceAppName = record.sourceAppName
                }
                try existing.update(db)
                return .promoted(existing)
            }

            try record.insert(db)
            return .inserted(record)
        }
    }

    /// Bulk insert for the legacy importer, in one transaction.
    ///
    /// Conflicts — on id or on content hash — are ignored rather than merged, so
    /// running the import a second time changes nothing. That is what lets the
    /// Settings "re-run import" button be safe to press.
    @discardableResult
    func importRecords(_ records: [ClipRecord], degraded: Int = 0) throws -> ImportSummary {
        try database.writer.write { db in
            var summary = ImportSummary(degraded: degraded)
            for record in records {
                try record.insert(db, onConflict: .ignore)
                if db.changesCount > 0 {
                    summary.imported += 1
                } else {
                    summary.skipped += 1
                }
            }
            return summary
        }
    }

    /// Attaches recognised text to a clip, making an image searchable.
    ///
    /// Passing `nil` clears both the text and its timestamp, which is what a
    /// failed re-run should leave behind — a clip that reads as "never
    /// recognised" rather than one stuck with a stale result.
    @discardableResult
    func setRecognizedText(_ text: String?, for id: String, at date: Date = Date()) throws -> ClipRecord? {
        try database.writer.write { db in
            guard var record = try ClipRecord.fetchOne(db, key: id) else { return nil }
            record.recognizedText = text
            record.recognizedAt = text == nil ? nil : date.timeIntervalSince1970
            try record.update(db)
            return record
        }
    }

    /// Deletes clips and returns the rows that went.
    ///
    /// Blobs and thumbnails are left on disk. Unlinking here would mean tracking
    /// how many rows share a content-addressed file, and getting that wrong
    /// deletes a file another clip is still showing. ``BlobStore/collectGarbage``
    /// sweeps orphans at launch instead: the failure mode is wasted bytes until
    /// the next launch rather than a broken clip, and it repairs itself.
    @discardableResult
    func delete(ids: [String]) throws -> [ClipRecord] {
        guard !ids.isEmpty else { return [] }
        return try database.writer.write { db in
            let doomed = try ClipRecord.filter(keys: ids).fetchAll(db)
            _ = try ClipRecord.deleteAll(db, keys: ids)
            return doomed
        }
    }

    func deleteAll() throws {
        _ = try database.writer.write { db in
            try ClipRecord.deleteAll(db)
        }
    }

    /// Applies a retention policy. Returns what was removed, files untouched.
    @discardableResult
    func prune(_ policy: RetentionPolicy, now: Date = Date()) throws -> [ClipRecord] {
        guard !policy.isUnlimited else { return [] }

        return try database.writer.write { db in
            var doomed: [String: ClipRecord] = [:]

            if let maximumAge = policy.maximumAge {
                let cutoff = now.timeIntervalSince1970 - maximumAge
                for record in try ClipRecord
                    .filter(ClipRecord.Columns.createdAt < cutoff)
                    .fetchAll(db)
                {
                    doomed[record.id] = record
                }
            }

            if let maximumCount = policy.maximumCount {
                // Everything past the newest N, in the same order the board shows.
                let overflow = try ClipRecord.fetchAll(db, sql: """
                    SELECT * FROM clip
                    ORDER BY created_at DESC, id DESC
                    LIMIT -1 OFFSET ?
                    """, arguments: [max(0, maximumCount)])
                for record in overflow {
                    doomed[record.id] = record
                }
            }

            guard !doomed.isEmpty else { return [] }
            _ = try ClipRecord.deleteAll(db, keys: Array(doomed.keys))
            return doomed.values.sorted { $0.createdAt > $1.createdAt }
        }
    }

    // MARK: - Reading

    func record(id: String) throws -> ClipRecord? {
        try database.writer.read { db in
            try ClipRecord.fetchOne(db, key: id)
        }
    }

    /// One screen's worth of clips, newest first.
    ///
    /// Pass the last record of the previous page as `before` to get the next one.
    func page(matching query: ClipQuery = .all, limit: Int, before cursor: ClipCursor? = nil) throws -> [ClipRecord] {
        try database.writer.read { db in
            try Self.fetchPage(db, query: query, limit: limit, before: cursor)
        }
    }

    func count(matching query: ClipQuery = .all) throws -> Int {
        try database.writer.read { db in
            let compiled = Self.compile(query, before: nil)
            return try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) \(compiled.source)",
                arguments: compiled.arguments
            ) ?? 0
        }
    }

    /// Every blob and thumbnail key still referenced by a row.
    ///
    /// The input to the launch-time file sweep. Anything on disk and not in here
    /// belongs to a clip that no longer exists.
    func liveKeys() throws -> (blobs: Set<String>, thumbnails: Set<String>) {
        try database.writer.read { db in
            // Every blob-bearing column, not just `blob_key`. A format added to
            // the schema and forgotten here would have its files collected out
            // from under the clips still using them.
            let blobs = try String.fetchSet(db, sql: """
                SELECT blob_key FROM clip WHERE blob_key IS NOT NULL
                UNION SELECT rtf_key FROM clip WHERE rtf_key IS NOT NULL
                UNION SELECT html_key FROM clip WHERE html_key IS NOT NULL
                """)
            let thumbnails = try String.fetchSet(
                db, sql: "SELECT DISTINCT thumb_key FROM clip WHERE thumb_key IS NOT NULL"
            )
            return (blobs, thumbnails)
        }
    }

    // MARK: - Observing

    /// A live page that re-fetches whenever `clip` changes.
    ///
    /// The tracked region is stated rather than inferred. A matched query also
    /// reads `clip_fts` and its shadow tables, and pinning the region to `clip`
    /// keeps what triggers a refresh obvious — the index only ever changes
    /// because `clip` did.
    func observePage(matching query: ClipQuery = .all, limit: Int) -> AsyncValueObservation<[ClipRecord]> {
        ValueObservation
            .tracking(regions: [Table("clip")]) { db in
                try Self.fetchPage(db, query: query, limit: limit, before: nil)
            }
            .values(in: database.writer)
    }

    // MARK: - Query compilation

    /// The `FROM … WHERE …` shared by paging and counting.
    private struct CompiledQuery {
        var source: String
        var arguments: StatementArguments
    }

    private static func compile(_ query: ClipQuery, before cursor: ClipCursor?) -> CompiledQuery {
        var source = "FROM clip"
        var arguments = StatementArguments()

        if let match = query.match {
            source += " JOIN clip_fts ON clip_fts.rowid = clip.rowid AND clip_fts MATCH ?"
            arguments += [match]
        }

        var conditions: [String] = []

        // Sets are unordered, so sort before interpolating: a stable SQL string is
        // what lets SQLite reuse the prepared statement across keystrokes.
        if !query.kinds.isEmpty {
            let kinds = query.kinds.map(\.rawValue).sorted()
            conditions.append("clip.kind IN (\(placeholders(kinds.count)))")
            arguments += StatementArguments(kinds)
        }

        if !query.bundleIDs.isEmpty {
            let bundleIDs = query.bundleIDs.sorted()
            conditions.append("clip.source_bundle_id IN (\(placeholders(bundleIDs.count)))")
            arguments += StatementArguments(bundleIDs)
        }

        // Typed, so fuzzy: "xcode" should find the app whether the user was
        // thinking of the name or the bundle identifier. Escaped, because a
        // search for "100%" must not turn into a wildcard that matches
        // everything.
        if let fragment = query.appFragment, !fragment.isEmpty {
            conditions.append("""
                (LOWER(clip.source_app_name) LIKE ? ESCAPE '\\' \
                OR LOWER(clip.source_bundle_id) LIKE ? ESCAPE '\\')
                """)
            let pattern = "%" + escapedForLike(fragment.lowercased()) + "%"
            arguments += [pattern, pattern]
        }

        if query.requiresRecognizedText {
            conditions.append("clip.recognized_text IS NOT NULL AND clip.recognized_text <> ''")
        }

        if let cursor {
            conditions.append("(clip.created_at < ? OR (clip.created_at = ? AND clip.id < ?))")
            arguments += [cursor.createdAt, cursor.createdAt, cursor.id]
        }

        if !conditions.isEmpty {
            source += " WHERE " + conditions.joined(separator: " AND ")
        }

        return CompiledQuery(source: source, arguments: arguments)
    }

    private static func fetchPage(
        _ db: Database,
        query: ClipQuery,
        limit: Int,
        before cursor: ClipCursor?
    ) throws -> [ClipRecord] {
        let compiled = Self.compile(query, before: cursor)
        // Ordered by time even when searching. FTS5 can rank by relevance, but a
        // clipboard history is something people navigate by *when* — a result set
        // that reshuffles as you type costs more than the better first hit gains.
        return try ClipRecord.fetchAll(db, sql: """
            SELECT clip.* \(compiled.source)
            ORDER BY clip.created_at DESC, clip.id DESC
            LIMIT ?
            """, arguments: compiled.arguments + [limit])
    }

    /// `%` and `_` are wildcards to LIKE and ordinary characters to a person.
    private static func escapedForLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }
}
