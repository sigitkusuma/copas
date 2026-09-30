import Foundation
import CloudKit

enum ServerChangeTokenCoder {
    static func encode(_ token: CKServerChangeToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    static func decode(from data: Data) -> CKServerChangeToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }
}

final class SyncDownloader: Sendable {
    private let repository: ClipRepository
    private let blobStore: BlobStore
    private let cloudKitManager: CloudKitManager

    init(repository: ClipRepository, blobStore: BlobStore, cloudKitManager: CloudKitManager) {
        self.repository = repository
        self.blobStore = blobStore
        self.cloudKitManager = cloudKitManager
    }

    /// Fetches all changes from CloudKit for the clips zone.
    /// Returns the number of changed/deleted records processed.
    @discardableResult
    func fetchChanges() async throws -> Int {
        let zoneID = cloudKitManager.zoneID
        let tokenData = try repository.serverChangeToken(for: zoneID.zoneName)
        let previousToken: CKServerChangeToken? = tokenData.flatMap(ServerChangeTokenCoder.decode)

        do {
            return try await executeFetchChangesOperation(previousToken: previousToken)
        } catch let error as CKError where error.code == .changeTokenExpired {
            Log.sync.notice("Server change token expired; resetting and performing full fetch")
            try repository.saveServerChangeToken(nil, for: zoneID.zoneName)
            return try await executeFetchChangesOperation(previousToken: nil)
        }
    }

    private func executeFetchChangesOperation(previousToken: CKServerChangeToken?) async throws -> Int {
        let zoneID = cloudKitManager.zoneID
        let repository = self.repository
        let blobStore = self.blobStore

        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        config.previousServerChangeToken = previousToken

        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: config]
            )

            let tracker = DownloadTracker()

            operation.recordWasChangedBlock = { recordID, result in
                switch result {
                case .success(let ckRecord):
                    let payload = ClipRecordMapper.clipRecord(from: ckRecord)
                    if let blobData = payload.blobData {
                        try? blobStore.write(blobData)
                    }
                    if let rtfData = payload.rtfData {
                        try? blobStore.write(rtfData)
                    }
                    if let htmlData = payload.htmlData {
                        try? blobStore.write(htmlData)
                    }
                    do {
                        try repository.upsertFromCloud(payload.record)
                        tracker.incrementChanged()
                    } catch {
                        Log.sync.error("Could not upsert cloud clip \(payload.record.id, privacy: .public): \(error, privacy: .public)")
                    }

                case .failure(let error):
                    Log.sync.error("Fetch record failed for \(recordID.recordName, privacy: .public): \(error, privacy: .public)")
                }
            }

            operation.recordWithIDWasDeletedBlock = { recordID, _ in
                do {
                    try repository.delete(ids: [recordID.recordName], recordSyncDeletion: false)
                    tracker.incrementDeleted()
                } catch {
                    Log.sync.error("Could not delete local clip for cloud deletion \(recordID.recordName, privacy: .public): \(error, privacy: .public)")
                }
            }

            operation.recordZoneChangeTokensUpdatedBlock = { updatedZoneID, token, _ in
                if let token, let data = ServerChangeTokenCoder.encode(token) {
                    try? repository.saveServerChangeToken(data, for: updatedZoneID.zoneName)
                }
            }

            operation.recordZoneFetchResultBlock = { fetchZoneID, result in
                switch result {
                case .success(let fetchResult):
                    if let data = ServerChangeTokenCoder.encode(fetchResult.serverChangeToken) {
                        try? repository.saveServerChangeToken(data, for: fetchZoneID.zoneName)
                    }
                case .failure(let error):
                    Log.sync.error("Zone fetch failed: \(error, privacy: .public)")
                }
            }

            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: tracker.totalCount)
                case .failure(let error):
                    if tracker.totalCount > 0 {
                        continuation.resume(returning: tracker.totalCount)
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }

            cloudKitManager.database.add(operation)
        }
    }
}

private final class DownloadTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var changedCount = 0
    private var deletedCount = 0

    func incrementChanged() {
        lock.lock()
        defer { lock.unlock() }
        changedCount += 1
    }

    func incrementDeleted() {
        lock.lock()
        defer { lock.unlock() }
        deletedCount += 1
    }

    var totalCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return changedCount + deletedCount
    }
}
