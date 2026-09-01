import Foundation

/// Where the board sits on screen.
///
/// Pure arithmetic, separated from the panel so the placement rules can be
/// checked without a window server — the interesting cases are all about screens
/// that are smaller, taller or positioned differently than the one being
/// developed on.
/// Which edge the board is anchored to.
///
/// A setting in waiting: the geometry is written for both so Settings can offer
/// the choice without any of this changing.
enum BoardEdge: String, Sendable, CaseIterable {
    case top
    case bottom
}

enum BoardGeometry {

    /// Anchored to one edge, spanning the full width.
    ///
    /// The top edge by default, tucked under the menu bar. That puts the board
    /// where the status item that opens it already is, and where the eye is
    /// already looking after a keystroke — a strip at the bottom means the
    /// pointer and the attention start at opposite ends of the screen.
    ///
    /// Measured against the screen's *visible* frame, so the board clears the
    /// menu bar at the top and rests on the Dock at the bottom, and is never
    /// taller than the space there is.
    static func frame(
        in visibleFrame: CGRect,
        edge: BoardEdge = .top,
        height: CGFloat = Theme.boardHeight
    ) -> CGRect {
        let height = min(height, visibleFrame.height)
        return CGRect(
            x: visibleFrame.minX,
            y: edge == .top ? visibleFrame.maxY - height : visibleFrame.minY,
            width: visibleFrame.width,
            height: height
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
