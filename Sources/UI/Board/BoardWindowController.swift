import AppKit
import SwiftUI

/// Shows and hides the board, and owns everything about *where* it is.
///
/// Split from ``BoardModel`` because the model has no business knowing about
/// screens, activation or which app had focus a moment ago — and because the
/// window mechanics here are the part that is hard-won and easy to break.
@MainActor
final class BoardWindowController {

    private let model: BoardModel
    private let thumbnails: ThumbnailStore
    private let paster: Paster
    private let monitor: PasteboardMonitor

    /// Read at each opening rather than captured once, so changing the setting
    /// takes effect on the very next Shift-Command-V.
    private let edge: () -> BoardEdge

    private var panel: BoardPanel?

    /// Captured *before* activating ourselves, because after that we are the
    /// frontmost application and the answer is gone. Everything about pasting
    /// into the right place depends on this one ordering.
    private var previousApp: NSRunningApplication?
    private var workspaceObserver: Any?
    private var resetObservers: [Any] = []

    /// Asked of the panel itself rather than remembered in a flag. A flag can
    /// say "open" about a window the system has since ordered out, and then
    /// every shortcut press would be spent on the dismissal of nothing.
    var isVisible: Bool { panel?.isVisible ?? false }

    init(
        model: BoardModel,
        thumbnails: ThumbnailStore,
        paster: Paster,
        monitor: PasteboardMonitor,
        edge: @escaping () -> BoardEdge = { .top }
    ) {
        self.model = model
        self.thumbnails = thumbnails
        self.paster = paster
        self.monitor = monitor
        self.edge = edge

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier != Bundle.main.bundleIdentifier {
                self.previousApp = app
                guard self.isVisible && !self.model.isPinnedToScreen && !self.model.isWritingToolsActive else {
                    return
                }
                // The notification can arrive after the board has already
                // taken over, describing an activation that happened before
                // the shortcut was pressed. Only a foreign app that is
                // frontmost *now* means the user has really moved on.
                guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                        != Bundle.main.bundleIdentifier else {
                    Log.app.notice("board: ignored a stale activation of \(app.bundleIdentifier ?? "?", privacy: .public)")
                    return
                }
                self.dismiss(restoringFocus: false, reason: "activated \(app.bundleIdentifier ?? "another app")")
            }
        }

        // A window that has sat hidden through sleep or a change of displays is
        // the one most likely to come back wrong, and a fresh panel costs
        // nothing. Dropped only while hidden, so a pinned board is never pulled
        // out from under the user.
        let resetEvents: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
        ]
        resetObservers = resetEvents.map { center, name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self, !self.isVisible, self.panel != nil else { return }
                Log.app.notice("board: dropped the hidden panel after \(name.rawValue, privacy: .public)")
                self.panel = nil
            }
        }

        model.onDismiss = { [weak self] in self?.dismiss() }
        model.onActivate = { [weak self] record, paste in
            self?.activate(record, paste: paste)
        }
    }

    deinit {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        for observer in resetObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Showing

    func toggle() {
        if isVisible {
            if model.isPinnedToScreen && panel?.isKeyWindow == false {
                NSApp.activate(ignoringOtherApps: true)
                panel?.makeKeyAndOrderFront(nil)
            } else {
                dismiss(reason: "toggled")
            }
        } else {
            show()
        }
    }

    func show() {
        guard !isVisible else { return }

        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }

        let panel = existingPanel()
        panel.setFrame(
            BoardGeometry.frame(
                in: targetScreen().visibleFrame,
                edge: edge(),
                cursor: NSEvent.mouseLocation
            ),
            display: false
        )

        model.start()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        Log.app.notice("board: shown, visible=\(panel.isVisible) key=\(panel.isKeyWindow)")
    }

    func dismiss(restoringFocus: Bool = true, reason: String = "requested") {
        guard isVisible else { return }
        Log.app.notice("board: dismissed — \(reason, privacy: .public)")
        model.isPinnedToScreen = false

        panel?.orderOut(nil)
        model.stop()

        if restoringFocus {
            previousApp?.activate()
        }
    }

    // MARK: - Paste

    /// Puts a clip back and, unless asked not to, presses ⌘V for it.
    private func activate(_ record: ClipRecord, paste: Bool) {
        let target = previousApp

        // Down first if not pinned to screen when pasting. The keystroke has to land in the other app,
        // and a panel still on screen would be the one holding focus when it arrives.
        // For copyWithoutPasting, the board stays open so the user can continue working.
        if paste && !model.isPinnedToScreen {
            dismiss(restoringFocus: false, reason: "pasted")
        }

        do {
            // Suppress before the paste, not after: the write has already moved
            // the change count and the poll could land in between.
            let changeCount = try paster.copy(record)
            monitor.suppress(upTo: changeCount)

            if paste {
                try paster.pressCommandV(into: target)
            } else {
                CaptureHUD.shared.show("Copied to clipboard", symbol: "checkmark")
            }
        } catch PasteError.notTrustedForAccessibility {
            // The clip is on the pasteboard regardless, so ⌘V by hand works.
            Log.app.notice("clip copied — Accessibility is needed to press ⌘V for you")
            if paste {
                target?.activate()
            }
            Paster.requestAccessibilityTrust()
        } catch {
            Log.app.error("could not paste: \(error, privacy: .public)")
            if paste {
                target?.activate()
            }
            NSSound.beep()
        }
    }

    // MARK: - Window

    private func existingPanel() -> BoardPanel {
        if let panel { return panel }

        let panel = BoardPanel(
            contentRect: BoardGeometry.frame(
                in: targetScreen().visibleFrame,
                edge: edge(),
                cursor: NSEvent.mouseLocation
            )
        )
        panel.contentView = NSHostingView(
            rootView: BoardView(model: model, thumbnails: thumbnails)
        )
        panel.onResignKey = { [weak self] in
            guard let self else { return }
            // When pinned to screen (scratchpad mode), do not dismiss on blur
            guard !self.model.isPinnedToScreen else { return }
            guard !self.model.isWritingToolsActive else { return }

            // Defer dismissal check to the next runloop turn so any transitioning system
            // panels (such as Apple Intelligence Writing Tools / Siri affordance or child windows)
            // have completed their focus transition, preventing unwanted dismissal out of the clipboard.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard !self.model.isPinnedToScreen else { return }
                guard !self.model.isWritingToolsActive else { return }
                guard let panel = self.panel else { return }
                guard !panel.isAnyWritingToolsActive else { return }
                guard !panel.isKeyWindow else { return }
                self.dismiss(restoringFocus: false, reason: "lost key")
            }
        }

        self.panel = panel
        return panel
    }

    /// Whichever screen the pointer is on.
    private func targetScreen() -> NSScreen {
        let pointer = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard let index = BoardGeometry.screenIndex(
            containing: pointer,
            among: screens.map(\.frame)
        ) else {
            return NSScreen.main ?? screens[0]
        }
        return screens[index]
    }
}
