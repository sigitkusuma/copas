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
                                    isSelected: model.selectedIDs.contains(card.id),
                                    thumbnails: thumbnails
                                )
                                .equatable()
                                .id(card.id)
                                // One click reads a clip in the pane beside
                                // it, immediately. A second click on the same
                                // row within the system double-click interval
                                // pastes it. ⌘-click and Shift-click multi-select.
                                .onTapGesture {
                                    let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                                    if flags.contains(.command) {
                                        model.toggleSelection(for: card.id)
                                    } else if flags.contains(.shift) {
                                        model.selectRange(to: card.id)
                                    } else {
                                        if model.isMultiSelecting {
                                            model.clearSelection()
                                        }
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
                                .contextMenu {
                                    clipContextMenu(for: card)
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

    // MARK: - Context Menu

    @ViewBuilder
    private func clipContextMenu(for card: ClipCardModel) -> some View {
        let isMulti = model.isMultiSelecting && model.selectedIDs.contains(card.id)

        if isMulti {
            let merged = ClipMergeUtility.merge(model.selectedCards.map { model.fullText(for: $0) })
            if !merged.isEmpty {
                ShareLink(item: merged) {
                    Label("Share Merged Clips...", systemImage: "square.and.arrow.up")
                }

                Button {
                    let texts = model.selectedCards.map { model.fullText(for: $0) }
                    ClipExportUtility.exportMerged(texts: texts)
                } label: {
                    Label("Export Merged as File...", systemImage: "arrow.down.doc")
                }

                Button {
                    model.mergeSelected()
                } label: {
                    Label("Merge & Copy (\(model.selectedIDs.count) clips)", systemImage: "doc.on.doc")
                }
            }

            Divider()

            Button(role: .destructive) {
                model.deleteSelected()
            } label: {
                Label("Delete (\(model.selectedIDs.count) clips)", systemImage: "trash")
            }
        } else {
            if card.kind == .text {
                let text = model.fullText(for: card)
                if !text.isEmpty {
                    ShareLink(item: text) {
                        Label("Share...", systemImage: "square.and.arrow.up")
                    }
                }

                Button {
                    ClipExportUtility.exportText(model.fullText(for: card))
                } label: {
                    Label("Export as File...", systemImage: "arrow.down.doc")
                }
            } else if card.kind == .image {
                if let data = model.imageData(for: card), let image = NSImage(data: data) {
                    ShareLink(item: Image(nsImage: image), preview: SharePreview("Image clip", image: Image(nsImage: image))) {
                        Label("Share...", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        ClipExportUtility.exportImage(data: data)
                    } label: {
                        Label("Export as File...", systemImage: "arrow.down.doc")
                    }
                }
            }

            Divider()

            Button {
                model.paste(card)
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }

            Button {
                model.copyWithoutPasting(card)
            } label: {
                Label("Copy to Clipboard", systemImage: "doc.on.doc")
            }

            Button {
                model.togglePin(for: card.id)
            } label: {
                Label(card.isPinned ? "Unpin" : "Pin", systemImage: card.isPinned ? "pin.slash" : "pin")
            }

            Divider()

            Button(role: .destructive) {
                model.delete(id: card.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

