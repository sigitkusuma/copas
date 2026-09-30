import Foundation
import CloudKit

final class SyncUploader: Sendable {
    private let repository: ClipRepository
    private let blobStore: BlobStore
    private let cloudKitManager: CloudKitManager

    init(repository: ClipRepository, blobStore: BlobStore, cloudKitManager: CloudKitManager) {
        self.repository = repository
        self.blobStore = blobStore
        self.cloudKitManager = cloudKitManager
    }

    /// Uploads pending records and deletions in batches.
    /// Returns the total number of items uploaded or deleted.
    @discardableResult
    func uploadPending(batchSize: Int = 100) async throws -> Int {
        let deletions = try repository.pendingDeletions(limit: batchSize)
        let pendingClips = try repository.pendingSyncRecords(limit: batchSize)

        if deletions.isEmpty && pendingClips.isEmpty {
            return 0
        }

        var recordsToSave: [CKRecord] = []
        var clipMap: [String: ClipRecord] = [:]

        for clip in pendingClips {
            clipMap[clip.id] = clip
            do {
                let ckRecord = try ClipRecordMapper.ckRecord(
                    from: clip,
                    zoneID: cloudKitManager.zoneID,
                    blobs: blobStore
                )
                recordsToSave.append(ckRecord)
            } catch {
                Log.sync.error("Failed to map clip \(clip.id, privacy: .public): \(error, privacy: .public)")
                try? repository.markSyncFailed(ids: [clip.id])
            }
        }

        let recordIDsToDelete = deletions.map {
            CKRecord.ID(recordName: $0.clipID, zoneID: cloudKitManager.zoneID)
        }

        do {
            return try await executeModifyOperation(
                recordsToSave: recordsToSave,
                recordIDsToDelete: recordIDsToDelete,
                clipMap: clipMap
            )
        } catch let error as CKError where error.code == .limitExceeded && batchSize > 10 {
            Log.sync.notice("CloudKit limit exceeded; retrying with smaller batch size")
            return try await uploadPending(batchSize: max(10, batchSize / 2))
        }
    }

    private func executeModifyOperation(
        recordsToSave: [CKRecord],
        recordIDsToDelete: [CKRecord.ID],
        clipMap: [String: ClipRecord]
    ) async throws -> Int {
        let repository = self.repository
        let blobStore = self.blobStore

        return try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(
                recordsToSave: recordsToSave.isEmpty ? nil : recordsToSave,
                recordIDsToDelete: recordIDsToDelete.isEmpty ? nil : recordIDsToDelete
            )
            operation.isAtomic = false
            operation.savePolicy = .allKeys

            let tracker = OperationTracker()

            operation.perRecordSaveBlock = { recordID, result in
                switch result {
                case .success(let savedRecord):
                    let modDate = savedRecord.modificationDate?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
                    try? repository.markSynced(ids: [recordID.recordName], cloudModifiedAt: modDate)
                    tracker.recordSaveSuccess(recordID.recordName)

                case .failure(let error):
                    if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                        if let serverRecord = ckError.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                            let serverPayload = ClipRecordMapper.clipRecord(from: serverRecord)
                            if let localClip = clipMap[recordID.recordName] {
                                if localClip.createdAt >= serverPayload.record.createdAt {
                                    // Local is newer or equal: keep pending so it retries
                                    Log.sync.info("Conflict: local clip is newer, will retry with update")
                                } else {
                                    // Server is newer: accept server payload
                                    if let blobData = serverPayload.blobData {
                                        try? blobStore.write(blobData)
                                    }
                                    if let rtfData = serverPayload.rtfData {
                                        try? blobStore.write(rtfData)
                                    }
                                    if let htmlData = serverPayload.htmlData {
                                        try? blobStore.write(htmlData)
                                    }
                                    _ = try? repository.upsertFromCloud(serverPayload.record)
                                    tracker.recordSaveSuccess(recordID.recordName)
                                }
                            }
                        }
                    } else {
                        Log.sync.error("Save failed for \(recordID.recordName, privacy: .public): \(error, privacy: .public)")
                        try? repository.markSyncFailed(ids: [recordID.recordName])
                    }
                }
            }

            operation.perRecordDeleteBlock = { recordID, result in
                switch result {
                case .success:
                    try? repository.removeSyncDeletions(ids: [recordID.recordName])
                    tracker.recordDeleteSuccess(recordID.recordName)

                case .failure(let error):
                    if let ckError = error as? CKError, ckError.code == .unknownItem {
                        try? repository.removeSyncDeletions(ids: [recordID.recordName])
                        tracker.recordDeleteSuccess(recordID.recordName)
                    } else {
                        Log.sync.error("Delete failed for \(recordID.recordName, privacy: .public): \(error, privacy: .public)")
                    }
                }
            }

            operation.modifyRecordsResultBlock = { result in
                let totalProcessed = tracker.totalSuccessCount
                switch result {
                case .success:
                    continuation.resume(returning: totalProcessed)
                case .failure(let error):
                    if totalProcessed > 0 {
                        continuation.resume(returning: totalProcessed)
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }

            cloudKitManager.database.add(operation)
        }
    }
}

private final class OperationTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var savedIDs: [String] = []
    private var deletedIDs: [String] = []

    func recordSaveSuccess(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        savedIDs.append(id)
    }

    func recordDeleteSuccess(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        deletedIDs.append(id)
    }

    var totalSuccessCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return savedIDs.count + deletedIDs.count
    }
}
