import Foundation

/// Where the board sits on screen.
///
/// Pure arithmetic, separated from the panel so the placement rules can be
/// checked without a window server — the interesting cases are all about screens
/// that are smaller, taller or positioned differently than the one being
/// developed on.
/// Which half of the screen the board is weighted towards.
///
/// It is always centred horizontally; this only decides whether the panel hangs
/// from the top of the free space or rests on the bottom of it.
enum BoardEdge: String, Sendable, CaseIterable {
    case top
    case bottom
    case cursor
}

enum BoardGeometry {

    /// A fixed-size panel, centred horizontally and weighted to one edge, or
    /// positioned near the mouse cursor.
    ///
    /// Centred rather than full-bleed because the board is now two panes — a
    /// list of clips and the whole of the selected one — and a list pane 1,500
    /// points from its detail pane would make the pairing invisible. Weighted
    /// upwards by default so it lands where the status item that opens it
    /// already is, and where the eye is already looking after a keystroke.
    ///
    /// Measured against the screen's *visible* frame, so the panel clears the
    /// menu bar and the Dock, and is never larger than the space there is.
    static func frame(
        in visibleFrame: CGRect,
        edge: BoardEdge = .top,
        cursor: CGPoint? = nil,
        size: CGSize = CGSize(width: Theme.boardWidth, height: Theme.boardHeight),
        inset: CGFloat = Theme.boardScreenInset
    ) -> CGRect {
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, visibleFrame.height)

        if edge == .cursor, let cursor {
            let minX = visibleFrame.minX + min(inset, max(0, (visibleFrame.width - width) / 2))
            let maxX = max(minX, visibleFrame.maxX - width - min(inset, max(0, (visibleFrame.width - width) / 2)))
            let rawX = cursor.x - width / 2
            let x = min(max(rawX, minX), maxX).rounded()

            let minY = visibleFrame.minY + min(inset, max(0, (visibleFrame.height - height) / 2))
            let maxY = max(minY, visibleFrame.maxY - height - min(inset, max(0, (visibleFrame.height - height) / 2)))
            let rawY = cursor.y - height / 2
            let y = min(max(rawY, minY), maxY).rounded()

            return CGRect(x: x, y: y, width: width, height: height)
        }

        // Rounded, because a panel on a half-point boundary renders its
        // hairline rules at two different weights on alternating edges.
        let x = (visibleFrame.minX + (visibleFrame.width - width) / 2).rounded()

        // The gap collapses rather than pushing the panel off a short screen.
        let gap = min(inset, visibleFrame.height - height)
        let y = edge == .bottom
            ? visibleFrame.minY + gap
            : visibleFrame.maxY - height - gap

        return CGRect(x: x, y: y.rounded(), width: width, height: height)
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
