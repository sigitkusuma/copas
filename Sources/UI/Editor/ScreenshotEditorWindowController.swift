import AppKit
import ImageIO
import SwiftUI

/// Opens the editor for one screenshot and reports what came of it.
///
/// A window rather than an overlay on the capture: the picture is already a
/// file by the time it arrives here, and an ordinary window can be moved aside,
/// resized and left alone while the user checks something in another app.
@MainActor
final class ScreenshotEditorWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var continuation: CheckedContinuation<Data?, Never>?
    private var model: ScreenshotEditorModel?

    /// Captured *before* this app comes forward, for the same reason the board
    /// does it: afterwards the answer is Copas. Handing focus back is what lets
    /// ⌘V work in the app the user was in the moment the editor closes.
    private var previousApp: NSRunningApplication?

    /// Shows the editor and waits. Returns the finished PNG, or `nil` when the
    /// user cancelled (or the picture could not be read).
    func edit(_ png: Data) async -> Data? {
        // One at a time; a second capture while one is open replaces nothing.
        guard continuation == nil else { return nil }

        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let model = ScreenshotEditorModel(base: image, sourceDPI: ScreenshotRenderer.dpi(of: png))
        self.model = model

        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }

        let window = makeWindow(for: model)
        self.window = window

        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            // Same three calls, same order, as the Settings window: a menu-bar
            // app is not active when the capture finishes, and
            // `makeKeyAndOrderFront` alone opens the window underneath.
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            window.orderFrontRegardless()
        }
    }

    private func makeWindow(for model: ScreenshotEditorModel) -> NSWindow {
        let view = ScreenshotEditorView(
            model: model,
            onDone: { [weak self] in self?.finish(save: true) },
            onCancel: { [weak self] in self?.finish(save: false) }
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize(for: model)),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Edit Screenshot"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    /// Big enough to show the picture at true size, within what the screen has.
    private func contentSize(for model: ScreenshotEditorModel) -> NSSize {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
        let imageWidth = CGFloat(model.base.width) / model.pixelsPerPoint
        let imageHeight = CGFloat(model.base.height) / model.pixelsPerPoint

        // Room for the canvas padding and the two bars around it.
        let width = min(max(imageWidth + 48, 680), visible.width * 0.9)
        let height = min(max(imageHeight + 48 + 100, 420), visible.height * 0.9)
        return NSSize(width: width, height: height)
    }

    private func finish(save: Bool) {
        guard let continuation else { return }
        self.continuation = nil

        let result = save ? model?.exportPNG() : nil

        window?.delegate = nil
        window?.orderOut(nil)
        window = nil
        model = nil

        previousApp?.activate()
        previousApp = nil

        continuation.resume(returning: result)
    }

    // MARK: - NSWindowDelegate

    /// The close button is a cancel, not a save: nothing is copied.
    func windowWillClose(_ notification: Notification) {
        finish(save: false)
    }
}
