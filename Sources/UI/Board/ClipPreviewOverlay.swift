import AppKit
import SwiftUI

/// The large look at one clip, on ⌘Y.
///
/// Deliberately modal and deliberately cheap to leave: ⌘Y closes it, Escape
/// closes it, clicking anywhere closes it. It is for reading something, not for
/// working in.
struct ClipPreviewOverlay: View {

    let card: ClipCardModel
    let text: String
    let imageData: Data?
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.35))
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 0) {
                header

                Rectangle().fill(Theme.rule).frame(height: 1)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: 720, maxHeight: Theme.boardHeight - 48)
            .background(Theme.canvas)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.ruleStrong, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
            .padding(24)
        }
        .transition(.opacity)
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let icon = AppIconCache.shared.icon(for: card.sourceBundleID) {
                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
            }
            Text(card.sourceName ?? "Unknown")
            Text("·").foregroundStyle(.quaternary)
            Text(card.detail)
            Spacer(minLength: 8)
            Text("⌘Y or Escape to close")
                .foregroundStyle(.quaternary)
        }
        .font(.system(size: Theme.metaSize))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 34)
    }

    @ViewBuilder
    private var content: some View {
        switch card.kind {
        case .text:
            ScrollView {
                Text(text)
                    .font(.system(size: 13, design: card.isMonospaced ? .monospaced : .default))
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(16)
            }

        case .image:
            VStack(spacing: 0) {
                ZStack {
                    Checkerboard()
                    if let imageData, let image = NSImage(data: imageData) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                }
                .padding(16)

                if card.hasRecognizedText, let recognized = card.recognizedText {
                    Rectangle().fill(Theme.rule).frame(height: 1)
                    ScrollView {
                        Text(recognized)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(16)
                    }
                    .frame(maxHeight: 140)
                }
            }
        }
    }
}
