import AppKit
import SwiftUI

/// One clip in the list pane: two lines of it, and where it came from.
///
/// Fixed height rather than measured, which is what keeps a long list smooth:
/// uniform rows let the lazy stack place everything arithmetically instead of
/// laying out each row to discover how tall it wants to be.
struct ClipRow: View, @MainActor Equatable {

    let model: ClipCardModel
    let isFocused: Bool
    let thumbnails: ThumbnailStore

    @State private var isHovered = false

    /// Only the two things a row can actually look different for.
    ///
    /// `thumbnails` is a constant for the board's lifetime and comparing it
    /// would mean nothing; leaving it out is what lets this be an
    /// `EquatableView` and skip the two hundred rows that did not change when
    /// focus moved by one.
    ///
    /// A main-actor-isolated conformance: SwiftUI only ever compares views while
    /// updating, which is on the main actor, and spelling that out is what lets
    /// the comparison read the view's own stored properties.
    static func == (lhs: ClipRow, rhs: ClipRow) -> Bool {
        lhs.model == rhs.model && lhs.isFocused == rhs.isFocused
    }

    var body: some View {
        HStack(spacing: 10) {
            if model.kind == .image {
                thumbnail
            }

            VStack(alignment: .leading, spacing: 2) {
                title
                meta
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.rowPadding)
        .frame(height: Theme.rowHeight)
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                    .fill(isFocused ? Theme.selection : (isHovered ? Theme.hover : Color.clear))

                // The one mark that survives at a glance. A tint alone is easy
                // to lose against a highlighted search term; a bar at the edge
                // is not.
                if isFocused {
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: 2)
                }
            }
            .padding(.vertical, 1)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(Theme.Motion.selection, value: isFocused)
        .animation(Theme.Motion.hover, value: isHovered)
        // One element, not five. See `accessibilityDescription`.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityDescription)
        .accessibilityAddTraits(isFocused ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Return pastes this clip")
    }

    // MARK: - Title

    @ViewBuilder
    private var title: some View {
        if model.listTitle.isEmpty {
            Text(model.kind == .image ? "Image" : "Empty")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        } else {
            // Highlighted here rather than in the card model, so the marking
            // runs for the handful of rows actually on screen instead of all
            // five hundred on every keystroke.
            Text(SearchHighlight.attributed(model.listTitle, terms: model.terms))
                .font(.system(size: 12, design: model.isMonospaced ? .monospaced : .default))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .truncationMode(.tail)
        }
    }

    // MARK: - Meta

    private var meta: some View {
        HStack(spacing: 5) {
            if let icon = AppIconCache.shared.icon(for: model.sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 11, height: 11)
            }

            Text(model.sourceName ?? "Unknown")
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Text("·").foregroundStyle(.quaternary)

            Text(model.timestamp)
                .monospacedDigit()
                .fixedSize()

            if model.hasRecognizedText {
                // The badge is the only thing that makes recognised text visible
                // as a feature rather than as invisible plumbing.
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 9))
                    .foregroundStyle(
                        model.matchSource == .recognizedText ? Theme.accent : Color.secondary
                    )
            }

            if model.matchSource == .body {
                // Says why this row is in the results when the match is past the
                // part of the clip the row was already showing.
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.accent)
            }

            Spacer(minLength: 0)
        }
        .font(.system(size: Theme.metaSize))
        .foregroundStyle(.tertiary)
    }

    // MARK: - Thumbnail

    private var thumbnail: some View {
        ZStack {
            Checkerboard()
            if let key = model.thumbnailKey, let image = thumbnails.cached(key) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // The thumbnail is genuinely absent — never a spinner, which
                // would promise something that is not coming.
                Image(systemName: "photo")
                    .font(.system(size: 13))
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(width: Theme.rowThumbnail, height: Theme.rowThumbnail)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Theme.rule, lineWidth: 1)
        }
    }
}
