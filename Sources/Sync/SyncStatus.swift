import Foundation
import Observation
import CloudKit

@MainActor
@Observable
final class SyncStatus {
    var isEntitled: Bool = true
    var isSyncing: Bool = false
    var lastSyncDate: Date?
    var errorMessage: String?
    var pendingCount: Int = 0
    var accountStatus: CKAccountStatus = .couldNotDetermine

    var isAccountAvailable: Bool {
        isEntitled && accountStatus == .available
    }

    var accountDescription: String {
        guard isEntitled else {
            return "Provisioning Profile Required"
        }
        switch accountStatus {
        case .available:
            return "Connected"
        case .noAccount:
            return "No iCloud Account"
        case .restricted:
            return "iCloud Restricted"
        case .couldNotDetermine:
            return errorMessage != nil ? "Unavailable" : "Checking..."
        case .temporarilyUnavailable:
            return "Temporarily Unavailable"
        @unknown default:
            return "Unknown"
        }
    }
}
