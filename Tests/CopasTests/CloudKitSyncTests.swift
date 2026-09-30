import Foundation
import Testing
import CloudKit
import GRDB

@testable import Copas

struct CloudKitSyncTests {

    let repository: ClipRepository
    let blobStore: BlobStore
    let tempDir: URL

    init() throws {
        self.repository = ClipRepository(database: try AppDatabase.inMemory())
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        self.tempDir = tempURL
        self.blobStore = BlobStore(root: tempURL)
    }

    private func createTextClip(
        _ text: String,
        id: String = UUID().uuidString,
        date: Date = Date(),
        isPinned: Bool = false
    ) throws -> ClipRecord {
        try ClipRecord.text(text, at: date, id: id, isPinned: isPinned) { data in
            try blobStore.write(data)
        }
    }

    // MARK: - Mapper Tests

    @Test func clipRecordMapperRoundTripsInlineTextClip() throws {
        let clip = try createTextClip("Hello CloudKit Sync!", id: "inline-clip-1", isPinned: true)
        let zoneID = CKRecordZone.ID(zoneName: "ClipHistory", ownerName: CKCurrentUserDefaultName)

        let ckRecord = try ClipRecordMapper.ckRecord(from: clip, zoneID: zoneID, blobs: blobStore)
        #expect(ckRecord.recordID.recordName == "inline-clip-1")
        #expect(ckRecord.recordID.zoneID == zoneID)
        #expect((ckRecord["isPinned"] as? NSNumber)?.intValue == 1)
        #expect((ckRecord["isInline"] as? NSNumber)?.intValue == 1)
        #expect(ckRecord["inlineText"] as? String == "Hello CloudKit Sync!")

        let payload = ClipRecordMapper.clipRecord(from: ckRecord)
        #expect(payload.record.id == clip.id)
        #expect(payload.record.kind == .text)
        #expect(payload.record.preview == clip.preview)
        #expect(payload.record.inlineText == clip.inlineText)
        #expect(payload.record.isPinned == true)
        #expect(payload.record.syncStatus == "synced")
        #expect(payload.blobData == nil)
    }

    @Test func clipRecordMapperRoundTripsBlobClip() throws {
        let largeString = String(repeating: "Large blob content across devices. ", count: 300)
        let clip = try createTextClip(largeString, id: "blob-clip-1")
        #expect(clip.isBlobBacked)
        #expect(clip.blobKey != nil)

        let zoneID = CKRecordZone.ID(zoneName: "ClipHistory", ownerName: CKCurrentUserDefaultName)
        let ckRecord = try ClipRecordMapper.ckRecord(from: clip, zoneID: zoneID, blobs: blobStore)

        #expect(ckRecord["blobAsset"] != nil)

        let payload = ClipRecordMapper.clipRecord(from: ckRecord)
        #expect(payload.record.id == clip.id)
        #expect(payload.record.kind == .text)
        #expect(payload.record.isInline == false)
        #expect(payload.record.syncStatus == "synced")
        #expect(payload.blobData != nil)
        #expect(payload.record.contentHash == clip.contentHash)
    }

    // MARK: - Repository Sync Methods

    @Test func repositoryTracksPendingSyncRecords() throws {
        let clip1 = try createTextClip("First clip", id: "c1")
        let clip2 = try createTextClip("Second clip", id: "c2")

        try repository.insert(clip1)
        try repository.insert(clip2)

        let pending = try repository.pendingSyncRecords()
        #expect(pending.count == 2)
        #expect(try repository.pendingSyncCount() == 2)

        try repository.markSynced(ids: ["c1"])
        let pendingAfter = try repository.pendingSyncRecords()
        #expect(pendingAfter.count == 1)
        #expect(pendingAfter.first?.id == "c2")
        #expect(try repository.pendingSyncCount() == 1)

        try repository.markSyncFailed(ids: ["c2"])
        let pendingAfterFailed = try repository.pendingSyncRecords()
        #expect(pendingAfterFailed.isEmpty)

        try repository.markAllPendingSync()
        #expect(try repository.pendingSyncCount() == 2)
    }

    @Test func repositoryTracksLocalDeletionsForSync() throws {
        let clip = try createTextClip("To be deleted", id: "del-1")
        try repository.insert(clip)

        // Delete with sync tracking enabled
        let deleted = try repository.delete(ids: ["del-1"], recordSyncDeletion: true)
        #expect(deleted.count == 1)

        let pendingDeletions = try repository.pendingDeletions()
        #expect(pendingDeletions.count == 1)
        #expect(pendingDeletions.first?.clipID == "del-1")

        try repository.removeSyncDeletions(ids: ["del-1"])
        let remainingDeletions = try repository.pendingDeletions()
        #expect(remainingDeletions.isEmpty)
    }

    @Test func repositoryUpsertFromCloudInsertsNewRecord() throws {
        let incoming = try createTextClip("From cloud Mac", id: "cloud-1", isPinned: true)
        let outcome = try repository.upsertFromCloud(incoming)

        #expect(outcome.isNew)
        #expect(outcome.record.id == "cloud-1")
        #expect(outcome.record.syncStatus == "synced")

        let stored = try repository.record(id: "cloud-1")
        #expect(stored?.preview == "From cloud Mac")
        #expect(stored?.isPinned == true)
        #expect(stored?.syncStatus == "synced")
    }

    @Test func repositoryUpsertFromCloudResolvesConflictsNewestWins() throws {
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let later = Date(timeIntervalSince1970: 1_700_000_100)

        // 1. Local is older, cloud is newer -> Cloud wins
        let localOld = try createTextClip("Old text", id: "conflict-1", date: earlier)
        try repository.insert(localOld)

        let cloudNew = try createTextClip("New text from cloud", id: "conflict-1", date: later)
        let outcome1 = try repository.upsertFromCloud(cloudNew)
        #expect(!outcome1.isNew)

        let stored1 = try repository.record(id: "conflict-1")
        #expect(stored1?.preview == "New text from cloud")
        #expect(stored1?.syncStatus == "synced")

        // 2. Local is newer, cloud is older -> Local preserved and marked pending
        let localNew = try createTextClip("Even newer text", id: "conflict-2", date: later)
        try repository.insert(localNew)
        try repository.markSynced(ids: ["conflict-2"])

        let cloudOld = try createTextClip("Old cloud text", id: "conflict-2", date: earlier)
        _ = try repository.upsertFromCloud(cloudOld)

        let stored2 = try repository.record(id: "conflict-2")
        #expect(stored2?.preview == "Even newer text")
        #expect(stored2?.syncStatus == "pending")
    }

    @Test func repositorySavesAndRetrievesServerChangeTokens() throws {
        let zoneName = "ClipHistory"
        let sampleData = "token-bytes-12345".data(using: .utf8)!

        let initialToken = try repository.serverChangeToken(for: zoneName)
        #expect(initialToken == nil)

        try repository.saveServerChangeToken(sampleData, for: zoneName)
        let savedToken = try repository.serverChangeToken(for: zoneName)
        #expect(savedToken == sampleData)

        try repository.saveServerChangeToken(nil, for: zoneName)
        let clearedToken = try repository.serverChangeToken(for: zoneName)
        #expect(clearedToken == nil)
    }

    @Test @MainActor func syncStatusReportsCorrectDefaults() {
        let status = SyncStatus()
        #expect(status.isSyncing == false)
        #expect(status.lastSyncDate == nil)
        #expect(status.errorMessage == nil)
        #expect(status.pendingCount == 0)
        #expect(status.isAccountAvailable == false)
        #expect(status.accountDescription == "Checking...")

        status.accountStatus = .available
        #expect(status.isAccountAvailable == true)
        #expect(status.accountDescription == "Connected")

        status.accountStatus = .noAccount
        #expect(status.isAccountAvailable == false)
        #expect(status.accountDescription == "No iCloud Account")
    }
}
