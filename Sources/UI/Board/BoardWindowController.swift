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

    private var panel: BoardPanel?

    /// Captured *before* activating ourselves, because after that we are the
    /// frontmost application and the answer is gone. Everything about pasting
    /// into the right place depends on this one ordering.
    private var previousApp: NSRunningApplication?

    private(set) var isVisible = false

    init(
        model: BoardModel,
        thumbnails: ThumbnailStore,
        paster: Paster,
        monitor: PasteboardMonitor
    ) {
        self.model = model
        self.thumbnails = thumbnails
        self.paster = paster
        self.monitor = monitor

        model.onDismiss = { [weak self] in self?.dismiss() }
        model.onActivate = { [weak self] record, paste in
            self?.activate(record, paste: paste)
        }
    }

    // MARK: - Showing

    func toggle() {
        isVisible ? dismiss() : show()
    }

    func show() {
        guard !isVisible else { return }

        previousApp = NSWorkspace.shared.frontmostApplication

        let panel = existingPanel()
        panel.setFrame(BoardGeometry.frame(in: targetScreen().visibleFrame), display: false)

        model.start()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        isVisible = true
    }

    func dismiss(restoringFocus: Bool = true) {
        guard isVisible else { return }
        isVisible = false

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

        // Down first. The keystroke has to land in the other app, and a panel
        // still on screen would be the one holding focus when it arrives.
        dismiss(restoringFocus: false)

        do {
            // Suppress before the paste, not after: the write has already moved
            // the change count and the poll could land in between.
            let changeCount = try paster.copy(record)
            monitor.suppress(upTo: changeCount)

            if paste {
                try paster.pressCommandV(into: target)
            } else {
                target?.activate()
            }
        } catch PasteError.notTrustedForAccessibility {
            // The clip is on the pasteboard regardless, so ⌘V by hand works.
            Log.app.notice("clip copied — Accessibility is needed to press ⌘V for you")
            target?.activate()
            Paster.requestAccessibilityTrust()
        } catch {
            Log.app.error("could not paste: \(error, privacy: .public)")
            target?.activate()
            NSSound.beep()
        }
    }

    // MARK: - Window

    private func existingPanel() -> BoardPanel {
        if let panel { return panel }

        let panel = BoardPanel(contentRect: BoardGeometry.frame(in: targetScreen().visibleFrame))
        panel.contentView = NSHostingView(
            rootView: BoardView(model: model, thumbnails: thumbnails)
        )
        panel.onResignKey = { [weak self] in
            // Already down when we lower it ourselves to paste; dismiss() is a
            // no-op then, which is what keeps this from fighting that path.
            self?.dismiss(restoringFocus: false)
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
