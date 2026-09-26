import AppKit

/// The window the board lives in.
///
/// An `NSPanel` rather than an `NSWindow` because a panel can take keyboard
/// focus without becoming the application's main window, which is what a
/// borderless strip summoned by a shortcut needs to be.
final class BoardPanel: NSPanel {

    var onResignKey: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isMovable = true
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none

        // `.fullScreenAuxiliary` is the one that matters: without it the board
        // simply cannot appear over an app in full screen, which is where a lot
        // of work actually happens. `.canJoinAllSpaces` keeps it from dragging
        // the user to another desktop, and `.stationary` keeps it still during
        // a Spaces switch instead of sliding along with the wallpaper.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    /// Borderless windows refuse key by default, and a board that cannot take a
    /// keystroke is not a board.
    override var canBecomeKey: Bool { true }

    /// Never main. Being main would make this the app's principal window and
    /// give it a place in the window menu, which for a transient strip is wrong.
    override var canBecomeMain: Bool { false }

    /// Checks whether any NSTextView within the panel currently has an active Writing Tools session.
    var isAnyWritingToolsActive: Bool {
        if #available(macOS 15.0, *) {
            func check(view: NSView) -> Bool {
                if let tv = view as? NSTextView, tv.isWritingToolsActive {
                    return true
                }
                return view.subviews.contains(where: check)
            }
            if let cv = contentView {
                return check(view: cv)
            }
        }
        return false
    }

    /// Losing focus means the user's attention went somewhere else, and a
    /// floating strip that outlives that is in the way. This is the only
    /// dismissal that is not a keystroke, and the one that makes the board feel
    /// like part of the system rather than an app you have to close.
    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
