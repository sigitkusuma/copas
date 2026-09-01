import Foundation

/// Where the board sits on screen.
///
/// Pure arithmetic, separated from the panel so the placement rules can be
/// checked without a window server — the interesting cases are all about screens
/// that are smaller, taller or positioned differently than the one being
/// developed on.
enum BoardGeometry {

    /// Anchored to the bottom edge, spanning the full width.
    ///
    /// Measured against the screen's *visible* frame, so the board rests on top
    /// of the Dock rather than underneath it, and never taller than the space
    /// there is.
    static func frame(in visibleFrame: CGRect, height: CGFloat = Theme.boardHeight) -> CGRect {
        CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width,
            height: min(height, visibleFrame.height)
        )
    }

    /// The screen the board should open on: whichever one the pointer is on.
    ///
    /// Following the pointer rather than the frontmost window, because the board
    /// is summoned by a keystroke and the pointer is the only thing that says
    /// where the user's attention actually is.
    static func screenIndex(containing point: CGPoint, among frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }
}
