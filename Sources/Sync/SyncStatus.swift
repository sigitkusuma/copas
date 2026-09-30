import Foundation
import Observation
import CloudKit

@MainActor
@Observable
final class SyncStatus {
    var isSyncing: Bool = false
    var lastSyncDate: Date?
    var errorMessage: String?
    var pendingCount: Int = 0
    var accountStatus: CKAccountStatus = .couldNotDetermine

    var isAccountAvailable: Bool {
        accountStatus == .available
    }

    var accountDescription: String {
        switch accountStatus {
        case .available:
            return "Connected"
        case .noAccount:
            return "No iCloud Account"
        case .restricted:
            return "iCloud Restricted"
        case .couldNotDetermine:
            return "Checking..."
        case .temporarilyUnavailable:
            return "Temporarily Unavailable"
        @unknown default:
            return "Unknown"
        }
    }
}
