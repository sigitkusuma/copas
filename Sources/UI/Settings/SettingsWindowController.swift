import AppKit
import SwiftUI

/// The Settings window.
///
/// Built by hand rather than with SwiftUI's `Settings` scene, which cannot open
/// at all in this app. Two things stack up: the scene is only ever presented for
/// an application whose activation policy is `.regular`, and Copas is
/// `LSUIElement`, so it is `.accessory` — and the private selector that asks for
/// the window, renamed once already from `showPreferencesWindow:` to
/// `showSettingsWindow:`, answers `true` whether or not anything appears. The
/// result is a menu item that silently does nothing, on every macOS the selector
/// has not yet been renamed again.
///
/// An `NSWindow` we own has neither problem, and matches how the board is built.
@MainActor
final class SettingsWindowController {

    private var window: NSWindow?
    private let content: () -> AnyView

    /// Built on first use rather than at launch: most sessions never open
    /// Settings, and the tabs read preferences and installed applications that
    /// are cheaper to gather when somebody asks.
    init<Content: View>(@ViewBuilder content: @escaping () -> Content) {
        self.content = { AnyView(content()) }
    }

    func show() {
        let window = existingWindow()
        if !window.isVisible { window.center() }

        // All three, in this order, and none of them is redundant.
        //
        // A menu-bar app is not the active application when its status item is
        // clicked, and `makeKeyAndOrderFront` only sorts a window among its own
        // app's — so on its own it opens the window underneath whatever you were
        // actually looking at, which reads exactly like Settings never opening
        // at all. `activate` asks for the app to come forward, and the system is
        // free to refuse an accessory app; `orderFrontRegardless` is the one
        // that does not take no for an answer.
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
    }

    private func existingWindow() -> NSWindow {
        if let window { return window }

        let view = NSHostingView(rootView: content())
        let window = SettingsWindow(
            contentRect: NSRect(origin: .zero, size: view.fittingSize),
            // Not resizable: the tabs are sized to the tallest of them, so there
            // is nothing a drag could reveal.
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Copas Settings"
        window.contentView = view

        // We hold the only reference. Without this, closing the window
        // deallocates it and the next click reaches freed memory.
        window.isReleasedWhenClosed = false

        self.window = window
        return window
    }
}

/// Restores ⌘W.
///
/// The shortcut normally comes from the standard Window menu, and an
/// `LSUIElement` app has no menu bar to put one in. Closing a settings window
/// with the keyboard is not something to have to reach for the mouse for.
private final class SettingsWindow: NSWindow {

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
