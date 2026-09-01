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

    /// Constructed here rather than in `applicationDidFinishLaunching`, because
    /// the Settings scene is built from the app's `body` and may be evaluated
    /// before launch finishes.
    let preferences = Preferences()

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

    // Capture to text.
    private let regionCapture = RegionCapture()

    private var updates: UpdateCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        openStore()
        startCapturing()
        registerHotkeys()

        // After the store, so a failure here cannot stop the app from being a
        // clipboard manager. An app that will not launch because it could not
        // ask about updates has its priorities backwards.
        updates = UpdateCoordinator(preferences: preferences)

        statusItem = StatusItemController(actions: StatusItemController.Actions(
            toggleBoard: { [weak self] in self?.toggleBoard() },
            captureToText: { [weak self] in self?.captureToText() },
            togglePause: { [weak self] in self?.togglePause() },
            isPaused: { [weak self] in self?.monitor?.isPaused ?? false },
            isCaptureToTextEnabled: { [weak self] in self?.preferences.isCaptureToTextEnabled ?? false },
            shortcuts: { [weak self] in
                guard let self else { return (.showBoard, .captureToText) }
                return (preferences.showBoardHotkey, preferences.captureToTextHotkey)
            },
            checkForUpdates: { [weak self] in self?.updates?.checkForUpdates() },
            openSettings: { [weak self] in self?.openSettings() },
            quit: { NSApp.terminate(nil) }
        ))
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
        let retention = preferences.retention
        Task.detached(priority: .utility) {
            do {
                let pruned = try clips.prune(retention)
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
        let recognition = ClipTextRecognition(clips: clips, blobs: blobs)

        // Detached, so the loop runs off the main thread. Ingesting hashes,
        // encodes a thumbnail and writes to disk — all of it work the monitor
        // deliberately does not do, precisely so it can happen somewhere else.
        let payloads = monitor.payloads
        captureTask = Task.detached(priority: .utility) { [weak self] in
            for await payload in payloads {
                do {
                    guard let outcome = try ingestor.ingest(payload) else { continue }

                    // Only for pictures the history has not seen before: copying
                    // the same screenshot twice should not read it twice.
                    guard outcome.isNew, outcome.record.kind == .image else { continue }
                    guard await self?.preferences.recognizesTextInImages == true else { continue }
                    await recognition.recognize(outcome.record)
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
            monitor: monitor,
            edge: { [weak self] in self?.preferences.boardEdge ?? .top }
        )

        applyExclusions()
    }

    /// Claims both shortcuts. Safe to call again after the user changes one.
    private func registerHotkeys() {
        let board = preferences.showBoardHotkey
        let claimed = hotkeys.register(.showBoard, combination: board) { [weak self] in
            self?.toggleBoard()
        }

        // Carbon refuses a combination another running app already holds, and a
        // shortcut that silently does nothing is indistinguishable from a broken
        // app. Saying so is the least this can do until Settings can show it.
        if !claimed {
            Log.app.error("""
                \(board.displayString, privacy: .public) is already claimed by \
                another app, so the shortcut will not fire
                """)
        }

        if preferences.isCaptureToTextEnabled {
            hotkeys.register(.captureToText, combination: preferences.captureToTextHotkey) { [weak self] in
                self?.captureToText()
            }
        } else {
            hotkeys.unregister(.captureToText)
        }
    }

    // MARK: - Settings

    /// The narrow set of things the Settings window can ask for.
    var settingsActions: SettingsActions {
        SettingsActions(
            reregisterHotkeys: { [weak self] in self?.registerHotkeys() },
            applyExclusions: { [weak self] in self?.applyExclusions() },
            applyRetention: { [weak self] in self?.applyRetention() },
            clipCount: { [weak self] in (try? self?.clips?.count()) ?? 0 },
            clearHistory: { [weak self] in self?.clearHistory() },
            checkForUpdates: { [weak self] in self?.updates?.checkForUpdates() },
            applyUpdateSettings: { [weak self] in
                guard let self else { return }
                updates?.checksAutomatically = preferences.checksForUpdatesAutomatically
                updates?.wantsBetaUpdates = preferences.receivesBetaUpdates
            }
        )
    }

    /// Pushed into the reader rather than read from it, so the capture path
    /// never reaches back into preferences on the hot poll.
    private func applyExclusions() {
        monitor?.reader.excludedBundleIDs = Set(preferences.excludedBundleIDs)
    }

    /// Trims immediately rather than waiting for the next launch: a user who has
    /// just lowered the limit expects the clips to be gone now.
    private func applyRetention() {
        guard let clips, let blobs, let thumbnails else { return }
        let retention = preferences.retention
        Task.detached(priority: .utility) {
            do {
                _ = try clips.prune(retention)
                let live = try clips.liveKeys()
                try blobs.collectGarbage(keeping: live.blobs)
                try thumbnails.collectGarbage(keeping: live.thumbnails)
            } catch {
                Log.store.error("could not apply retention: \(error, privacy: .public)")
            }
        }
    }

    private func clearHistory() {
        guard let clips, let blobs, let thumbnails else { return }
        do {
            try clips.deleteAll()
            try blobs.collectGarbage(keeping: [])
            try thumbnails.collectGarbage(keeping: [])
        } catch {
            Log.store.error("could not clear the history: \(error, privacy: .public)")
            NSSound.beep()
        }
    }

    private func togglePause() {
        guard let monitor else { return }
        monitor.isPaused ? monitor.resume() : monitor.pause()
        statusItem?.refresh()
    }

    // MARK: - Actions

    private func toggleBoard() {
        guard let board else {
            NSSound.beep()
            return
        }
        board.toggle()
    }

    // MARK: - Capture to text

    /// Drag out a region of the screen and get its text on the clipboard.
    ///
    /// The image never reaches the clipboard when there is text in it — the point
    /// is to skip the retyping, not to collect screenshots. The write is
    /// deliberately *not* suppressed, so the recognised text lands in history
    /// like anything else copied.
    private func captureToText() {
        guard RegionCapture.requestPermission() else { return }

        Task { @MainActor in
            switch await regionCapture.selectRegion() {
            case .cancelled:
                // Escape. A normal way to change your mind, not a failure.
                return
            case .failed:
                CaptureHUD.shared.show("Capture failed", symbol: "exclamationmark.triangle")
            case .captured(let data):
                await finish(capture: data)
            }
        }
    }

    private func finish(capture data: Data) async {
        guard let image = ClipTextRecognition.decode(data) else {
            CaptureHUD.shared.show("Capture failed", symbol: "exclamationmark.triangle")
            return
        }

        let text = (await TextRecognizer.recognizeText(in: image))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if text.isEmpty {
            guard preferences.copiesImageWhenNoTextFound else {
                CaptureHUD.shared.show("No text found", symbol: "text.viewfinder")
                return
            }
            // Never throw away what the user just took the trouble to select.
            // A picture they have to read themselves beats nothing at all.
            pasteboard.setData(data, forType: .png)
            CaptureHUD.shared.show("No text — image copied", symbol: "photo")
        } else {
            pasteboard.setString(text, forType: .string)
            CaptureHUD.shared.show("Text copied", symbol: "text.viewfinder")
        }
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
