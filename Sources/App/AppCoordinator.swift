import AppKit
import SwiftUI

/// Owns every long-lived object in the app and wires them together.
///
/// Deliberately the only place that knows how the pieces fit. Collaborators are
/// injected downward and hold references to each other only where the data
/// actually flows — there is no shared store singleton and no
/// `NotificationCenter` string-name bus for app-internal signalling, both of
/// which make call graphs impossible to follow once there are more than three
/// participants.
@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {

    private var statusItem: StatusItemController?
    private let hotkeys = HotkeyCenter()

    // The data layer. Optional because a database that will not open should
    // leave a running app with a status item and an explanation, not a crash.
    private var database: AppDatabase?
    private var clips: ClipRepository?
    private var blobs: BlobStore?
    private var thumbnails: ThumbnailStore?

    // Capture and paste.
    private var monitor: PasteboardMonitor?
    private var paster: Paster?
    private var captureTask: Task<Void, Never>?

    // The board.
    private var board: BoardWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        openStore()
        startCapturing()
        registerHotkeys()

        statusItem = StatusItemController(
            onToggleBoard: { [weak self] in self?.toggleBoard() },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        captureTask?.cancel()
        hotkeys.unregisterAll()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Store

    private func openStore() {
        do {
            let locations = try StorageLocations.standard()
            let database = try AppDatabase.onDisk(at: locations)
            let clips = ClipRepository(database: database)
            let blobs = BlobStore(root: locations.blobsDirectory)
            let thumbnails = ThumbnailStore(
                root: locations.thumbnailsDirectory,
                maximumPixelSize: Int(Theme.thumbnailMaxPixel)
            )

            self.database = database
            self.clips = clips
            self.blobs = blobs
            self.thumbnails = thumbnails

            tidyUp(clips: clips, blobs: blobs, thumbnails: thumbnails)
        } catch {
            // Phase 7 gives this a visible home in Settings. Until then the log is
            // the honest place for it — better than an alert the user cannot act on.
            Log.store.error("could not open the clip store: \(error, privacy: .public)")
        }
    }

    /// Applies retention and deletes files no clip refers to any more.
    ///
    /// Once per launch, off the main thread, and in this order: pruning first
    /// means the sweep that follows also collects whatever pruning just orphaned,
    /// rather than leaving it for the launch after next.
    private func tidyUp(clips: ClipRepository, blobs: BlobStore, thumbnails: ThumbnailStore) {
        Task.detached(priority: .utility) {
            do {
                let pruned = try clips.prune(.default)
                let live = try clips.liveKeys()
                let removedBlobs = try blobs.collectGarbage(keeping: live.blobs)
                let removedThumbnails = try thumbnails.collectGarbage(keeping: live.thumbnails)

                if pruned.count + removedBlobs + removedThumbnails > 0 {
                    Log.store.info("""
                        tidied up: \(pruned.count) clips pruned, \
                        \(removedBlobs) blobs and \(removedThumbnails) thumbnails collected
                        """)
                }
            } catch {
                // Nothing here is required for the app to work — a failed sweep
                // costs disk space until the next launch and nothing else.
                Log.store.error("launch tidy-up failed: \(error, privacy: .public)")
            }
        }
    }

    // MARK: - Capture

    private func startCapturing() {
        guard let clips, let blobs, let thumbnails else { return }

        let monitor = PasteboardMonitor()
        let ingestor = ClipIngestor(clips: clips, blobs: blobs, thumbnails: thumbnails)

        // Detached, so the loop runs off the main thread. Ingesting hashes,
        // encodes a thumbnail and writes to disk — all of it work the monitor
        // deliberately does not do, precisely so it can happen somewhere else.
        let payloads = monitor.payloads
        captureTask = Task.detached(priority: .utility) {
            for await payload in payloads {
                do {
                    try ingestor.ingest(payload)
                } catch {
                    Log.store.error("could not store a clip: \(error, privacy: .public)")
                }
            }
        }

        monitor.start()
        let paster = Paster(blobs: blobs)

        self.monitor = monitor
        self.paster = paster
        self.board = BoardWindowController(
            model: BoardModel(clips: clips, blobs: blobs),
            thumbnails: thumbnails,
            paster: paster,
            monitor: monitor
        )
    }

    private func registerHotkeys() {
        let claimed = hotkeys.register(.showBoard, combination: .showBoard) { [weak self] in
            self?.toggleBoard()
        }

        // Carbon refuses a combination another running app already holds. The
        // likeliest cause by far is the app this replaces still running, and
        // saying so beats leaving a shortcut that does nothing.
        if !claimed {
            Log.app.error("""
                \(KeyCombination.showBoard.displayString, privacy: .public) is already \
                claimed by another app, so the shortcut will not fire
                """)
        }
    }

    // MARK: - Actions

    private func toggleBoard() {
        guard let board else {
            NSSound.beep()
            return
        }
        board.toggle()
    }

    private func openSettings() {
        // The selector moved in macOS 14; the older one silently does nothing.
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
