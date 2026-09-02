import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The board: a list of clips, the whole of the selected one beside it, and the
/// keys that drive both.
struct BoardView: View {

    @Bindable var model: BoardModel
    let thumbnails: ThumbnailStore

    var body: some View {
        ZStack {
            Theme.canvas

            VStack(spacing: 0) {
                SearchBar(model: model)

                ThemeSeparator()

                ZStack {
                    if model.hasNoResults {
                        noResults
                    } else if model.isEmpty {
                        emptyState
                    } else {
                        panes
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ThemeSeparator()

                hints
            }

            if let card = model.previewedCard {
                ClipPreviewOverlay(
                    card: card,
                    text: model.fullText(for: card),
                    imageData: model.imageData(for: card),
                    onDismiss: { model.togglePreview() }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The panel is borderless and floats over whatever is behind it, so the
        // hairline runs the whole way round rather than along one edge.
        .clipShape(RoundedRectangle(cornerRadius: Theme.boardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.boardRadius, style: .continuous)
                .strokeBorder(Theme.ruleStrong, lineWidth: 1)
        }
        .animation(Theme.Motion.contentIn, value: model.previewedID)
        .background(KeyMonitor(handler: handle))
    }

    // MARK: - The two panes

    private var panes: some View {
        HStack(spacing: 0) {
            ClipList(model: model, thumbnails: thumbnails)
                .frame(width: Theme.listWidth)

            Rectangle()
                .fill(Theme.rule)
                .frame(width: 1)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let card = model.focusedCard {
            ClipDetail(
                card: card,
                terms: model.query.terms,
                loadText: { model.fullText(for: $0) },
                loadImage: { model.imageData(for: $0) }
            )
        } else {
            ClipDetailPlaceholder()
        }
    }

    private var emptyState: some View {
        message(
            icon: "doc.on.clipboard",
            title: "Nothing copied yet",
            detail: "Copy something and it will appear here."
        )
    }

    /// Distinct from the empty state on purpose. "Nothing copied yet" on a full
    /// history because of a typo would be alarming, and offers no way out.
    private var noResults: some View {
        message(
            icon: "magnifyingglass",
            title: "No clips match",
            detail: "Escape clears the search."
        )
    }

    private func message(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.quaternary)
            Text(title)
                .font(.system(size: Theme.titleSize))
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.system(size: Theme.metaSize))
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Always shown, always dim. A hint that appears on hover is a hint nobody
    /// reads, because it is not there while you are wondering what to press.
    private var hints: some View {
        HStack(spacing: 14) {
            hint("↑↓", "Move")
            hint("↩", "Paste")
            hint("⌘↩", "Copy")
            hint("⌘Y", "Expand")
            hint("⌘⌫", "Delete")
            hint("⎋", model.isSearching ? "Clear" : "Close")
            Spacer(minLength: 0)
        }
        .font(.system(size: Theme.metaSize))
        .foregroundStyle(.quaternary)
        .padding(.horizontal, Theme.gutter)
        // Read once as a summary rather than as twelve disconnected glyphs, and
        // skipped entirely when arrowing through clips.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Keyboard shortcuts: up and down arrows move through clips, "
            + "Return pastes, Command Return copies, Command Y expands, "
            + "Command Delete deletes, Escape "
            + (model.isSearching ? "clears the search" : "closes the board")
        )
        .frame(height: Theme.hintBarHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.canvasSubtle)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).monospaced()
            Text(label)
        }
    }

    // MARK: - Keys

    /// How far Page Up and Page Down move: a screenful of the list pane, near
    /// enough, without asking the view how tall it turned out to be.
    private static let pageStep = Int(
        (Theme.boardHeight - Theme.searchBarHeight - Theme.hintBarHeight) / Theme.rowHeight
    ) - 1

    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommand = flags.contains(.command)
        let hasOption = flags.contains(.option)

        // ⌘1 through ⌘9: paste the nth clip without moving through them first.
        if hasCommand, !hasOption,
           let characters = event.charactersIgnoringModifiers,
           let digit = Int(characters), (1...9).contains(digit) {
            model.paste(at: digit - 1)
            return true
        }

        switch Int(event.keyCode) {
        // The list runs down the pane now, so the selection moves with ↑ and ↓.
        // ← and → are deliberately not claimed: they belong to the caret in the
        // search field, which is where typing goes.
        case kVK_UpArrow:
            hasOption ? model.moveFocusBySection(-1) : model.moveFocus(by: -1)
        case kVK_DownArrow:
            hasOption ? model.moveFocusBySection(1) : model.moveFocus(by: 1)
        case kVK_PageUp:
            model.moveFocus(by: -Self.pageStep)
        case kVK_PageDown:
            model.moveFocus(by: Self.pageStep)
        case kVK_Home:
            model.focusFirst()
        case kVK_End:
            model.focusLast()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            hasCommand ? model.copyWithoutPasting() : model.paste()
        case kVK_Escape:
            model.escape()

        // Expand and delete carry a modifier because the caret lives in the
        // search field: Space has to type a space and Delete has to delete a
        // character, or searching for anything with a word break in it is
        // impossible. Binding them conditionally on whether the field is empty
        // would be worse — a key that does two different things depending on
        // state you cannot see.
        case kVK_ANSI_Y where hasCommand:
            model.togglePreview()
        case kVK_Delete where hasCommand:
            model.deleteFocused()

        default:
            // Everything else reaches the search field, which is what makes
            // typing anywhere search — and what keeps ⌘Q, ⌘V and input methods
            // working.
            return false
        }
        return true
    }
}
