import AppKit
import SwiftUI

/// The grey grid that says "this part is transparent".
///
/// One tiled image rather than a `Canvas` drawing squares. A pane-sized
/// checkerboard is several hundred rectangles, redrawn on every pass; this is a
/// single tile the compositor repeats.
struct Checkerboard: View {

    var body: some View {
        Image(nsImage: Self.tile)
            .resizable(resizingMode: .tile)
            .opacity(0.5)
    }

    @MainActor
    private static let tile: NSImage = {
        let square: CGFloat = 8
        let image = NSImage(size: NSSize(width: square * 2, height: square * 2))
        image.lockFocus()

        NSColor.textBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: square * 2, height: square * 2).fill()

        NSColor.quaternaryLabelColor.setFill()
        NSRect(x: 0, y: 0, width: square, height: square).fill()
        NSRect(x: square, y: square, width: square, height: square).fill()

        image.unlockFocus()
        return image
    }()
}
