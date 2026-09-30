import Foundation
import CloudKit

final class CloudKitManager: Sendable {
    static let containerIdentifier = "iCloud.com.sigitkusuma.copas"
    static let zoneName = "ClipHistory"
    static let subscriptionID = "clip-history-changes"

    let container: CKContainer
    let database: CKDatabase
    let zoneID: CKRecordZone.ID
    let zone: CKRecordZone

    init(container: CKContainer = CKContainer(identifier: containerIdentifier)) {
        self.container = container
        self.database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
        self.zoneID = zoneID
        self.zone = CKRecordZone(zoneID: zoneID)
    }

    func checkAccountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    func setupZone() async throws {
        do {
            _ = try await database.save(zone)
            Log.sync.info("CloudKit zone '\(Self.zoneName, privacy: .public)' created or verified")
        } catch let error as CKError where error.code == .serverRejectedRequest || error.code == .zoneNotFound {
            Log.sync.info("Zone setup note: \(error.localizedDescription, privacy: .public)")
        } catch {
            Log.sync.error("Zone setup error: \(error, privacy: .public)")
            throw error
        }
    }

    func setupSubscription() async throws {
        let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: Self.subscriptionID)
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await database.save(subscription)
            Log.sync.info("CloudKit subscription created")
        } catch let error as CKError where error.code == .serverRejectedRequest {
            Log.sync.info("CloudKit subscription already exists")
        } catch {
            Log.sync.error("CloudKit subscription setup failed: \(error, privacy: .public)")
            throw error
        }
    }
}
