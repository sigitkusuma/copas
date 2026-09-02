import SwiftUI

/// The left pane: every clip the current search matches, newest first, grouped
/// by the day it was captured.
struct ClipList: View {

    @Bindable var model: BoardModel
    let thumbnails: ThumbnailStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(model.sections) { section in
                        Section {
                            ForEach(section.cards) { card in
                                ClipRow(
                                    model: card,
                                    isFocused: card.id == model.focusedID,
                                    thumbnails: thumbnails
                                )
                                .equatable()
                                .id(card.id)
                                // Two gestures, both cheap to discover: one
                                // click reads a clip in the pane beside it,
                                // two puts it back where you were typing.
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
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
                .scrollTargetLayout()
            }
            // Scrolling a row to the top of the list would put it exactly under
            // the pinned day header. This is the room the header needs.
            .contentMargins(.top, Theme.sectionHeaderHeight, for: .scrollContent)
            .scrollIndicators(.automatic)
            // `scrollTo` with no anchor scrolls the least it can to bring the
            // row into view — so arrowing through the middle of the list leaves
            // it still, and it only moves once focus reaches an edge.
            .onChange(of: model.scrollAnchorID) { _, id in
                guard let id else { return }
                withAnimation(Theme.Motion.selection) { proxy.scrollTo(id) }
            }
            // The panel is hidden and shown rather than rebuilt, so the list
            // still holds the scroll offset it had five minutes ago while the
            // model has already gone back to the newest clip.
            .onChange(of: model.isVisibleGeneration) {
                guard let id = model.focusedID else { return }
                proxy.scrollTo(id, anchor: .top)
            }
        }
        // A whisper of tint, which is all it takes to read as a sidebar rather
        // than as the same page split by a line.
        .background(Theme.canvasSubtle.background(Theme.canvas))
    }
}
