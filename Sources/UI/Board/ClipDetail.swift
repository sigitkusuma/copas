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
    let onTransform: (TextTransform) -> Void
    let onDismiss: () -> Void
    let onTogglePin: () -> Void
    var onSaveText: ((String) -> Void)? = nil

    @State private var text = ""
    @State private var originalText = ""
    @State private var image: NSImage?
    @State private var justSaved = false

    private var isModified: Bool {
        card.kind == .text && text != originalText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ThemeSeparator()

            // Action bar: quick actions + transforms + Writing Tools. Text clips only.
            if card.kind == .text {
                ClipActionBar(
                    text: text,
                    card: card,
                    onTransform: { transform in
                        onTransform(transform)
                    },
                    onDismiss: onDismiss
                )
                ThemeSeparator()
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Button("") {
                if isModified {
                    saveChanges()
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .opacity(0)
        }
        // Keyed on the clip: arrowing down the list cancels the load in flight
        // and starts the one for the row you actually landed on.
        .task(id: card.id) {
            text = ""
            originalText = ""
            image = nil
            justSaved = false
            switch card.kind {
            case .text:
                let loaded = loadText(card)
                text = loaded
                originalText = loaded
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

            HStack(spacing: 8) {
                if isModified {
                    Button {
                        text = originalText
                    } label: {
                        Text("Revert")
                            .font(.system(size: Theme.metaSize))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Discard edits")

                    Button {
                        saveChanges()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark")
                            Text("Save")
                        }
                        .font(.system(size: Theme.metaSize, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("Update clip & clipboard (⌘S)")
                } else if justSaved {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                        Text("Updated")
                    }
                    .font(.system(size: Theme.metaSize, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .transition(.opacity)
                }

                if card.kind == .text && !text.isEmpty {
                    ShareLink(item: text) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Share clip")
                } else if card.kind == .image, let image {
                    ShareLink(item: Image(nsImage: image), preview: SharePreview("Image clip", image: Image(nsImage: image))) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Share image")
                }

                Button {
                    if card.kind == .text {
                        ClipExportUtility.exportText(text)
                    } else if card.kind == .image, let data = loadImage(card) {
                        ClipExportUtility.exportImage(data: data)
                    }
                } label: {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Export as file...")

                Button {
                    onTogglePin()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: card.isPinned ? "pin.fill" : "pin")
                            .foregroundStyle(card.isPinned ? Theme.bookmark : .secondary)
                        Text(card.isPinned ? "Pinned" : "Pin")
                            .foregroundStyle(card.isPinned ? Theme.bookmark : .secondary)
                    }
                    .font(.system(size: Theme.metaSize))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(card.isPinned ? Theme.bookmark.opacity(0.12) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help(card.isPinned ? "Unpin clip (⌘P)" : "Pin clip (⌘P)")
            }
        }
        .font(.system(size: Theme.metaSize))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, Theme.detailPadding)
        .frame(height: 34)
        .accessibilityElement(children: .combine)
    }

    private func saveChanges() {
        guard isModified else { return }
        originalText = text
        onSaveText?(text)
        withAnimation(Theme.Motion.contentIn) {
            justSaved = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(Theme.Motion.contentIn) {
                justSaved = false
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch card.kind {
        case .text:
            ClipTextView(
                text: $text,
                isMonospaced: card.isMonospaced,
                terms: terms,
                onTextChange: { _ in }
            )
            .padding(Theme.detailPadding)

        case .image:
            VStack(spacing: 0) {
                ZStack {
                    Checkerboard()
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .onDrag {
                                if let data = loadImage(card) {
                                    return ClipDragItemProvider.itemProvider(forImageData: data, id: card.id)
                                }
                                return NSItemProvider()
                            }
                            .help("Drag to copy image to any app")
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
