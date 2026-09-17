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
                // Top drag bar for moving the panel
                HStack {
                    Spacer()
                    Capsule()
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 36, height: 4)
                    Spacer()
                }
                .frame(height: 10)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .background(WindowDragView())

                SearchBar(model: model)

                FilterBar(model: model)

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
        if model.isMultiSelecting {
            MultiSelectDetail(model: model)
        } else if let card = model.focusedCard {
            ClipDetail(
                card: card,
                terms: model.query.terms,
                loadText: { model.fullText(for: $0) },
                loadImage: { model.imageData(for: $0) },
                onTransform: { model.copyTransformed($0) },
                onDismiss: { model.onDismiss?() },
                onTogglePin: { model.togglePin(for: card.id) },
                onSaveText: { newText in
                    model.updateText(newText, for: card.id)
                },
                onPaste: { model.paste() },
                onCopy: { model.copyWithoutPasting() }
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
            if model.isMultiSelecting {
                hint("⌘M", "Merge")
                hint("⌘⌫", "Delete (\(model.selectedIDs.count))")
                hint("⎋", "Deselect")
            } else {
                hint("↑↓", "Move")
                hint("↩", "Paste")
                hint("⌘1-9", "Quick")
                hint("Space", "Preview")
                hint("⌘⇧P", model.isPinnedToScreen ? "Unpin Win" : "Pin Win")
                hint("⌘P", model.focusedCard?.isPinned == true ? "Unpin" : "Pin")
                hint("⌘T", "Transform")
                hint("⌘⌫", "Delete")
                hint("⎋", model.isSearching ? "Clear" : "Close")
            }
            Spacer(minLength: 0)

            if model.isPinnedToScreen {
                HStack(spacing: 4) {
                    Image(systemName: "pin.fill")
                    Text("Pinned to Screen")
                }
                .font(.system(size: Theme.metaSize, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Theme.selection)
                .clipShape(Capsule())
            }
        }
        .font(.system(size: Theme.metaSize))
        .foregroundStyle(.secondary)
        .padding(.horizontal, Theme.gutter)
        // Read once as a summary rather than as twelve disconnected glyphs, and
        // skipped entirely when arrowing through clips.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Keyboard shortcuts: up and down arrows move through clips, "
            + "Return pastes, Command Return copies, Command Y expands, "
            + "Command T transforms, "
            + "Command Delete deletes, Escape "
            + (model.isSearching ? "clears the search" : "closes the board")
        )
        .frame(height: Theme.hintBarHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.canvasSubtle)
        .background(WindowDragView())
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).monospaced().foregroundStyle(.primary)
            Text(label).foregroundStyle(.secondary)
        }
    }

    // MARK: - Keys

    /// How far Page Up and Page Down move: a screenful of the list pane, near
    /// enough, without asking the view how tall it turned out to be.
    private static let pageStep = Int(
        (Theme.boardHeight - Theme.searchBarHeight - Theme.hintBarHeight)
            / (Theme.rowHeight + Theme.rowSpacing)
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
            if flags.contains(.shift) {
                if let current = model.focusedCard { model.toggleSelection(for: current.id) }
                model.moveFocus(by: -1)
                if let next = model.focusedCard { model.toggleSelection(for: next.id) }
            } else {
                if model.isMultiSelecting { model.clearSelection() }
                hasOption ? model.moveFocusBySection(-1) : model.moveFocus(by: -1)
            }
        case kVK_DownArrow:
            if flags.contains(.shift) {
                if let current = model.focusedCard { model.toggleSelection(for: current.id) }
                model.moveFocus(by: 1)
                if let next = model.focusedCard { model.toggleSelection(for: next.id) }
            } else {
                if model.isMultiSelecting { model.clearSelection() }
                hasOption ? model.moveFocusBySection(1) : model.moveFocus(by: 1)
            }
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

        case kVK_Space:
            if model.previewedID != nil {
                model.togglePreview()
            } else if model.searchText.isEmpty {
                model.togglePreview()
            } else {
                return false
            }

        case kVK_ANSI_Y where hasCommand:
            model.togglePreview()
        case kVK_Delete where hasCommand:
            model.isMultiSelecting ? model.deleteSelected() : model.deleteFocused()
        case kVK_ANSI_T where hasCommand:
            model.showTransforms = true
        case kVK_ANSI_P where hasCommand:
            if flags.contains(.shift) {
                model.togglePinToScreen()
            } else {
                model.togglePinFocused()
            }
        case kVK_ANSI_M where hasCommand:
            model.mergeSelected()

        default:
            // Everything else reaches the search field, which is what makes
            // typing anywhere search — and what keeps ⌘Q, ⌘V and input methods
            // working.
            return false
        }
        return true
    }
}
