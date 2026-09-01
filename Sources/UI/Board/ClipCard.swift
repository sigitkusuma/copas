import AppKit
import SwiftUI

/// One clip, at a fixed size.
///
/// Fixed rather than measured, which is what keeps a long strip smooth: uniform
/// cards let the lazy stack place everything arithmetically instead of laying
/// out each card to discover how tall it wants to be.
struct ClipCard: View, @MainActor Equatable {

    let model: ClipCardModel
    let isFocused: Bool
    let thumbnails: ThumbnailStore

    /// Only the two things a card can actually look different for.
    ///
    /// `thumbnails` is a constant for the board's lifetime and comparing it
    /// would mean nothing; leaving it out is what lets this be an
    /// `EquatableView` and skip the two hundred cards that did not change when
    /// focus moved by one.
    /// A main-actor-isolated conformance: SwiftUI only ever compares views while
    /// updating, which is on the main actor, and spelling that out is what lets
    /// the comparison read the view's own stored properties.
    static func == (lhs: ClipCard, rhs: ClipCard) -> Bool {
        lhs.model == rhs.model && lhs.isFocused == rhs.isFocused
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle()
                .fill(Theme.rule)
                .frame(height: 1)
            body(for: model)
            Rectangle()
                .fill(Theme.rule)
                .frame(height: 1)
            footer
        }
        .frame(width: Theme.cardWidth, height: Theme.cardHeight, alignment: .topLeading)
        .background(isFocused ? Theme.selection : Theme.canvasSubtle)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(
                    isFocused ? Theme.accent : Theme.rule,
                    lineWidth: isFocused ? Theme.focusRingWidth : 1
                )
        }
        .animation(Theme.Motion.selection, value: isFocused)
        // One element, not six. See `accessibilityDescription`.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityDescription)
        .accessibilityAddTraits(isFocused ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Return pastes this clip")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            if let icon = AppIconCache.shared.icon(for: model.sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 13, height: 13)
            } else {
                Image(systemName: model.kind == .image ? "photo" : "doc.plaintext")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(width: 13, height: 13)
            }

            Text(model.sourceName ?? "Unknown")
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            Text(model.timestamp)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: Theme.metaSize))
        .foregroundStyle(.secondary)
        .padding(.horizontal, Theme.cardPadding)
        .frame(height: 30)
    }

    // MARK: - Body

    @ViewBuilder
    private func body(for model: ClipCardModel) -> some View {
        switch model.kind {
        case .text:
            TextCardBody(
                text: model.displayText,
                terms: model.terms,
                isMonospaced: model.isMonospaced
            )
        case .image:
            ImageCardBody(
                thumbnail: model.thumbnailKey.flatMap { thumbnails.cached($0) },
                caption: model.recognizedCaption,
                terms: model.terms
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 4) {
            if model.hasRecognizedText {
                // The badge is the only thing that makes recognised text visible
                // as a feature rather than as invisible plumbing.
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 9))
                    .foregroundStyle(model.matchSource == .recognizedText ? Theme.accent : Color.secondary)
            }
            if model.matchSource == .body {
                // Says why this card is in the results when the match is past the
                // part of the clip the card was already showing.
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.accent)
            }
            Text(model.detail)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: Theme.metaSize))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, Theme.cardPadding)
        .frame(height: 26)
    }
}
