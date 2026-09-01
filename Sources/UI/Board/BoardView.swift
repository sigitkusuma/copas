import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The strip of cards, and the keys that drive it.
struct BoardView: View {

    @Bindable var model: BoardModel
    let thumbnails: ThumbnailStore

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.canvas

            if model.isEmpty {
                emptyState
            } else {
                strip
            }

            hints

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
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.quaternary)
            Text("Nothing copied yet")
                .font(.system(size: Theme.titleSize))
                .foregroundStyle(.secondary)
            Text("Copy something and it will appear here.")
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
            hint("Space", "Preview")
            hint("⌫", "Delete")
            hint("⎋", "Close")
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
        case kVK_Delete, kVK_ForwardDelete:
            model.deleteFocused()
        case kVK_Space:
            model.togglePreview()
        case kVK_Escape:
            model.escape()
        default:
            // Everything else falls through, which is what keeps ⌘Q working.
            return false
        }
        return true
    }
}
