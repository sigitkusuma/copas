import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The strip of cards, and the keys that drive it.
struct BoardView: View {

    @Bindable var model: BoardModel
    let thumbnails: ThumbnailStore

    var body: some View {
        ZStack {
            Theme.canvas

            VStack(spacing: 0) {
                SearchBar(model: model)

                Rectangle()
                    .fill(Theme.rule)
                    .frame(height: 1)

                ZStack {
                    if model.hasNoResults {
                        noResults
                    } else if model.isEmpty {
                        emptyState
                    } else {
                        strip
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            hints
                .frame(maxHeight: .infinity, alignment: .bottom)

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
        // The hairline goes on the edge facing the rest of the screen, which for
        // a board hanging from the menu bar is the bottom one.
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.ruleStrong).frame(height: 1)
        }
        .animation(Theme.Motion.contentIn, value: model.previewedID)
        .background(KeyMonitor(handler: handle))
    }

    // MARK: - The strip

    private var strip: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Theme.cardGap, pinnedViews: [.sectionHeaders]) {
                ForEach(model.sections) { section in
                    Section {
                        ForEach(section.cards) { card in
                            ClipCard(
                                model: card,
                                isFocused: card.id == model.focusedID,
                                thumbnails: thumbnails
                            )
                            .equatable()
                            .id(card.id)
                            .onTapGesture(count: 2) {
                                model.focusedID = card.id
                                model.paste()
                            }
                            .onTapGesture {
                                model.focusedID = card.id
                            }
                        }
                    } header: {
                        DayHeader(label: section.label)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.gutter)
            .padding(.bottom, Theme.hintBarHeight + 12)
            .scrollTargetLayout()
        }
        .scrollPosition(id: $model.scrollAnchorID)
        // Scrolling to a card aligns it with the leading edge — which is exactly
        // where the pinned day rail sits. Without this inset, every card the
        // keyboard moves to arrives half-hidden behind the rail.
        .contentMargins(.leading, Theme.dayRailWidth, for: .scrollContent)
        .scrollIndicators(.never)
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
    }

    /// Always shown, always dim. A hint that appears on hover is a hint nobody
    /// reads, because it is not there while you are wondering what to press.
    private var hints: some View {
        HStack(spacing: 14) {
            hint("↩", "Paste")
            hint("⌘↩", "Copy")
            hint("⌘Y", "Preview")
            hint("⌘⌫", "Delete")
            hint("⎋", model.isSearching ? "Clear" : "Close")
            Spacer(minLength: 0)
        }
        .font(.system(size: Theme.metaSize))
        .foregroundStyle(.quaternary)
        .padding(.horizontal, Theme.gutter)
        .frame(height: Theme.hintBarHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).monospaced()
            Text(label)
        }
    }

    // MARK: - Keys

    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommand = flags.contains(.command)
        let hasOption = flags.contains(.option)

        // ⌘1 through ⌘9: paste the nth card without moving through them first.
        if hasCommand, !hasOption,
           let characters = event.charactersIgnoringModifiers,
           let digit = Int(characters), (1...9).contains(digit) {
            model.paste(at: digit - 1)
            return true
        }

        switch Int(event.keyCode) {
        case kVK_LeftArrow:
            hasOption ? model.moveFocusBySection(-1) : model.moveFocus(by: -1)
        case kVK_RightArrow:
            hasOption ? model.moveFocusBySection(1) : model.moveFocus(by: 1)
        case kVK_Home:
            model.focusFirst()
        case kVK_End:
            model.focusLast()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            hasCommand ? model.copyWithoutPasting() : model.paste()
        case kVK_Escape:
            model.escape()

        // Preview and delete carry a modifier because the caret lives in the
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
