import Foundation
import CloudKit
import Security

final class CloudKitManager: Sendable {
    static let containerIdentifier = "iCloud.com.sigitkusuma.copas"
    static let zoneName = "ClipHistory"
    static let subscriptionID = "clip-history-changes"

    static var isEntitled: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        guard let value = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.icloud-container-identifiers" as CFString,
            nil
        ) as? [String] else {
            return false
        }
        return value.contains(containerIdentifier)
    }

    let container: CKContainer?
    let database: CKDatabase?
    let zoneID: CKRecordZone.ID
    let zone: CKRecordZone

    init(container: CKContainer? = nil) {
        if let container {
            self.container = container
            self.database = container.privateCloudDatabase
        } else if Self.isEntitled {
            let c = CKContainer(identifier: Self.containerIdentifier)
            self.container = c
            self.database = c.privateCloudDatabase
        } else {
            self.container = nil
            self.database = nil
        }
        let zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
        self.zoneID = zoneID
        self.zone = CKRecordZone(zoneID: zoneID)
    }

    func checkAccountStatus() async throws -> CKAccountStatus {
        guard let container else {
            return .couldNotDetermine
        }
        return try await container.accountStatus()
    }

    func setupZone() async throws {
        guard let database else { return }
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
        guard let database else { return }
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
