import AppKit
import SwiftUI

/// The one-time window shown after the first launch.
///
/// A plain `NSWindow` we own, same as ``SettingsWindowController`` and for the
/// same reason: `LSUIElement` apps cannot rely on a SwiftUI `Scene` to present
/// itself, or on `NSApp.activate` alone to bring it to the front of whatever the
/// user was already looking at.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let content: () -> AnyView

    /// Called once, however the window closes — the "Get Started" button, the
    /// red close button, or `⌘W`. Whichever the user reached for, they are done
    /// looking at it, and it should not come back next launch.
    var onClose: () -> Void = {}

    init<Content: View>(@ViewBuilder content: @escaping () -> Content) {
        self.content = { AnyView(content()) }
    }

    func show() {
        let window = existingWindow()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    private func existingWindow() -> NSWindow {
        if let window { return window }

        let view = NSHostingView(rootView: content())
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: view.fittingSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Copas"
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.window = window
        return window
    }
}
