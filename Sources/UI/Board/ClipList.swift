import AppKit
import SwiftUI

/// The left pane: every clip the current search matches, newest first, grouped
/// by the day it was captured.
struct ClipList: View {

    @Bindable var model: BoardModel
    let thumbnails: ThumbnailStore

    /// Tracks the last row tapped and when, so a second click on the same row
    /// can be treated as a double-click without attaching a `count: 2` tap
    /// gesture alongside the single-tap one. SwiftUI has to wait out the
    /// double-click interval before it can commit to the single-tap gesture
    /// when both are on the same view, which is what made every click feel
    /// delayed. Tracking the timing by hand keeps the single click instant.
    @State private var lastTap: (id: ClipCardModel.ID, date: Date)?

    private static let doubleClickInterval: TimeInterval = NSEvent.doubleClickInterval

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: Theme.rowSpacing, pinnedViews: [.sectionHeaders]) {
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
                                // One click reads a clip in the pane beside
                                // it, immediately. A second click on the same
                                // row within the system double-click interval
                                // pastes it — tracked by hand rather than
                                // with a `count: 2` gesture, which would
                                // force the single click to wait and see.
                                .onTapGesture {
                                    let now = Date()
                                    if let lastTap, lastTap.id == card.id,
                                       now.timeIntervalSince(lastTap.date) < Self.doubleClickInterval {
                                        model.paste()
                                        self.lastTap = nil
                                    } else {
                                        model.focusedID = card.id
                                        lastTap = (card.id, now)
                                    }
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
