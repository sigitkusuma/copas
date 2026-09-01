import AppKit
import Foundation
import Sparkle

/// Checks for new versions, and installs them.
///
/// A thin wrapper on `SPUStandardUpdaterController`, which is deliberate: the
/// interesting parts of updating — signature checking, staged installs, the
/// relaunch dance — are exactly the parts nobody should reimplement.
@MainActor
final class UpdateCoordinator: NSObject {

    private var controller: SPUStandardUpdaterController!
    private let channel = ChannelPreference()

    init(preferences: Preferences) {
        super.init()

        channel.wantsBeta = preferences.receivesBetaUpdates

        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        controller.updater.automaticallyChecksForUpdates = preferences.checksForUpdatesAutomatically
    }

    /// The menu item and the button in Settings.
    ///
    /// `activate` first, because the app has no Dock icon: without it Sparkle's
    /// sheet opens behind whatever the user was looking at, and the app appears
    /// to have done nothing.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.updater.checkForUpdates()
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    var checksAutomatically: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var wantsBetaUpdates: Bool {
        get { channel.wantsBeta }
        set { channel.wantsBeta = newValue }
    }

    var lastCheck: Date? {
        controller.updater.lastUpdateCheckDate
    }
}

extension UpdateCoordinator: SPUUpdaterDelegate {

    /// Opting in to pre-releases rather than filtering them after the fact.
    ///
    /// A channel is decided by the *feed*, so a build that is not marked beta is
    /// never offered to someone who did not ask — which is the failure the
    /// previous app's "include prereleases" flag could not prevent, because by
    /// then the update had already been chosen.
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        channel.wantsBeta ? ["beta"] : []
    }
}

/// Sparkle asks for the channel from its own scheduling machinery, and the
/// delegate method is not main-actor isolated. One flag behind a lock is the
/// whole of the shared state, so that is what this is.
private final class ChannelPreference: @unchecked Sendable {

    private let lock = NSLock()
    private var storage = false

    var wantsBeta: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storage = newValue
        }
    }
}
