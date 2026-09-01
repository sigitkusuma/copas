import AppKit
import SwiftUI

/// A text snippet, set monospaced when it looks like code.
struct TextCardBody: View {

    let text: String
    let isMonospaced: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 12, design: isMonospaced ? .monospaced : .default))
            .lineSpacing(2)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Theme.cardPadding)
            .clipped()
            // Text that runs past the card fades out rather than being cut
            // mid-stroke, so it reads as "there is more" instead of as a bug.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.86),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

/// A thumbnail over a checkerboard, with recognised text underneath it.
struct ImageCardBody: View {

    let thumbnail: NSImage?
    let recognizedText: String?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Checkerboard()
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    // The thumbnail is genuinely absent — never a spinner, which
                    // would promise something that is not coming.
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(.quaternary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            if let recognizedText, !recognizedText.isEmpty {
                Text(recognizedText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.cardPadding)
                    .padding(.vertical, 6)
                    .background(Theme.canvas)
            }
        }
    }
}

/// The grey grid that says "this part is transparent".
///
/// One tiled image rather than a `Canvas` drawing squares. A card-sized
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
