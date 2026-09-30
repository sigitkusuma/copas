import Foundation
import CloudKit
import AppKit

@MainActor
final class SyncEngine: Sendable {
    let cloudKitManager: CloudKitManager
    let uploader: SyncUploader
    let downloader: SyncDownloader
    let status: SyncStatus
    private let repository: ClipRepository
    private let blobStore: BlobStore
    private let thumbnailStore: ThumbnailStore

    private var observationTask: Task<Void, Never>?
    private var syncDebounceTask: Task<Void, Never>?
    private var isStarted = false

    init(
        clips: ClipRepository,
        blobs: BlobStore,
        thumbnails: ThumbnailStore,
        cloudKitManager: CloudKitManager = CloudKitManager()
    ) {
        self.repository = clips
        self.blobStore = blobs
        self.thumbnailStore = thumbnails
        self.cloudKitManager = cloudKitManager
        self.uploader = SyncUploader(repository: clips, blobStore: blobs, cloudKitManager: cloudKitManager)
        self.downloader = SyncDownloader(repository: clips, blobStore: blobs, cloudKitManager: cloudKitManager)
        self.status = SyncStatus()
    }

    func start() async {
        guard !isStarted else { return }
        isStarted = true

        do {
            let accountStatus = try await cloudKitManager.checkAccountStatus()
            status.accountStatus = accountStatus

            guard accountStatus == .available else {
                Log.sync.notice("CloudKit account is not available: \(String(describing: accountStatus))")
                return
            }

            try await cloudKitManager.setupZone()
            try await cloudKitManager.setupSubscription()

            startObservingPending()

            await syncNow()
        } catch {
            status.errorMessage = error.localizedDescription
            Log.sync.error("SyncEngine start failed: \(error, privacy: .public)")
        }
    }

    func stop() {
        isStarted = false
        observationTask?.cancel()
        observationTask = nil
        syncDebounceTask?.cancel()
        syncDebounceTask = nil
    }

    func syncNow() async {
        guard isStarted, !status.isSyncing else { return }
        status.isSyncing = true
        status.errorMessage = nil

        defer {
            status.isSyncing = false
        }

        do {
            _ = try await downloader.fetchChanges()
            _ = try await uploader.uploadPending()
            status.lastSyncDate = Date()
            status.pendingCount = (try? repository.pendingSyncCount()) ?? 0
        } catch {
            status.errorMessage = error.localizedDescription
            Log.sync.error("Sync cycle failed: \(error, privacy: .public)")
        }
    }

    func handleRemoteNotification() async {
        guard isStarted else { return }
        Log.sync.info("Handling remote notification for sync")
        do {
            _ = try await downloader.fetchChanges()
            status.lastSyncDate = Date()
        } catch {
            Log.sync.error("Remote notification sync failed: \(error, privacy: .public)")
        }
    }

    func scheduleUpload() {
        guard isStarted else { return }
        syncDebounceTask?.cancel()
        syncDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.syncNow()
        }
    }

    private func startObservingPending() {
        observationTask?.cancel()
        let observation = repository.observePendingSyncCount()
        observationTask = Task { [weak self] in
            do {
                for try await count in observation {
                    guard let self else { break }
                    self.status.pendingCount = count
                    if count > 0 {
                        self.scheduleUpload()
                    }
                }
            } catch {
                Log.sync.error("Pending sync observation failed: \(error, privacy: .public)")
            }
        }
    }
}
