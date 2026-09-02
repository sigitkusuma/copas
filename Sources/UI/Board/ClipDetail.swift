import AppKit
import SwiftUI

/// The right pane: the whole of the selected clip.
///
/// The list shows two lines and a source; this shows everything, at a measure
/// wide enough to read. Content is loaded in a `.task` keyed on the clip rather
/// than read in `body`, because a clip's text can live in a blob on disk and
/// `body` runs again for every keystroke in the search field.
struct ClipDetail: View {

    let card: ClipCardModel
    let terms: [String]
    /// Handed in rather than reached for, so this view never holds the model
    /// and never has to know where a blob lives.
    let loadText: (ClipCardModel) -> String
    let loadImage: (ClipCardModel) -> Data?

    @State private var text = ""
    @State private var image: NSImage?

    /// Highlighting walks the whole string, so it is worth doing for the clip
    /// you are looking at and not worth doing for a 400 KB log file.
    private static let highlightLimit = 20_000

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ThemeSeparator()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Keyed on the clip: arrowing down the list cancels the load in flight
        // and starts the one for the row you actually landed on.
        .task(id: card.id) {
            text = ""
            image = nil
            switch card.kind {
            case .text:
                text = loadText(card)
            case .image:
                image = loadImage(card).flatMap(NSImage.init(data:))
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            if let icon = AppIconCache.shared.icon(for: card.sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
            }

            Text(card.sourceName ?? "Unknown")
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("·").foregroundStyle(.quaternary)
            Text(card.timestamp).monospacedDigit()
            Text("·").foregroundStyle(.quaternary)
            Text(card.detail)

            Spacer(minLength: 8)
        }
        .font(.system(size: Theme.metaSize))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, Theme.detailPadding)
        .frame(height: 34)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch card.kind {
        case .text:
            ScrollView {
                Text(attributedText)
                    .font(.system(size: 13, design: card.isMonospaced ? .monospaced : .default))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(Theme.detailPadding)
            }
            // A clip that fills the pane should not look like one that ends
            // exactly at the bottom edge, so the scroll bar stays visible.
            .scrollIndicators(.automatic)

        case .image:
            VStack(spacing: 0) {
                ZStack {
                    Checkerboard()
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        DelayedProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(Theme.detailPadding)

                if let recognized = card.recognizedText, !recognized.isEmpty {
                    ThemeSeparator()
                    recognizedPanel(recognized)
                }
            }
        }
    }

    private func recognizedPanel(_ recognized: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Text in image", systemImage: "text.viewfinder")
                .font(.system(size: Theme.metaSize, weight: .medium))
                .foregroundStyle(.tertiary)

            ScrollView {
                Text(SearchHighlight.attributed(recognized, terms: terms))
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, Theme.detailPadding)
        .padding(.vertical, 12)
        .frame(maxHeight: 150, alignment: .top)
        .background(Theme.canvasSubtle)
    }

    /// Marks the search terms, but only while the clip is small enough that
    /// walking it costs less than the answer is worth.
    private var attributedText: AttributedString {
        guard !terms.isEmpty, text.count <= Self.highlightLimit else {
            return AttributedString(text)
        }
        return SearchHighlight.attributed(text, terms: terms)
    }
}

/// Nothing selected — an empty history, or the instant before the first clip
/// arrives.
struct ClipDetailPlaceholder: View {

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.quaternary)
            Text("Select a clip")
                .font(.system(size: Theme.metaSize))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}
