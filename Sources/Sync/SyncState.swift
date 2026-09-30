import Foundation
import GRDB

struct SyncState: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sync_state"

    var zoneID: String
    var serverChangeToken: Data?
    var lastSyncAt: Double?

    var id: String { zoneID }

    enum CodingKeys: String, CodingKey {
        case zoneID = "zone_id"
        case serverChangeToken = "server_change_token"
        case lastSyncAt = "last_sync_at"
    }

    enum Columns {
        static let zoneID = Column(CodingKeys.zoneID)
        static let serverChangeToken = Column(CodingKeys.serverChangeToken)
        static let lastSyncAt = Column(CodingKeys.lastSyncAt)
    }
}

struct SyncDeletion: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sync_deletion"

    var clipID: String
    var deletedAt: Double

    var id: String { clipID }

    enum CodingKeys: String, CodingKey {
        case clipID = "clip_id"
        case deletedAt = "deleted_at"
    }

    enum Columns {
        static let clipID = Column(CodingKeys.clipID)
        static let deletedAt = Column(CodingKeys.deletedAt)
    }
}
