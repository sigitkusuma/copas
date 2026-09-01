import AppKit
import Foundation
import Observation

/// All of the board's state, in one place.
///
/// `@Observable` rather than `ObservableObject`, and a model rather than two
/// dozen `@State` properties inside the view. The app this replaces kept its
/// window state as twenty-five separate `@State` values in a single 2,000-line
/// view, which made "what happens when the user presses Return" a question you
/// could only answer by reading all of it. Here the view draws and this decides.
@MainActor
@Observable
final class BoardModel {

    // MARK: - What the view draws

    private(set) var sections: [ClipSection] = []
    private(set) var isLoaded = false

    /// The card the keyboard is on.
    var focusedID: String? {
        didSet {
            guard focusedID != oldValue else { return }
            scrollAnchorID = focusedID
        }
    }

    /// Kept separate from ``focusedID`` because `scrollPosition(id:)` is a two-way
    /// binding: scrolling by hand writes back into it. Sharing one property would
    /// mean dragging the strip silently moved the selection.
    var scrollAnchorID: String?

    /// The card shown large, or `nil`. Space toggles it.
    private(set) var previewedID: String?

    var isEmpty: Bool { isLoaded && sections.isEmpty }

    // MARK: - Collaborators

    @ObservationIgnored private let clips: ClipRepository
    @ObservationIgnored private let blobs: BlobStore
    @ObservationIgnored private var records: [ClipRecord] = []
    @ObservationIgnored private var now = Date()
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?

    /// Handed a clip and whether to press ⌘V for it. The model does not know
    /// which app had focus before the board opened, and should not.
    @ObservationIgnored var onActivate: ((ClipRecord, _ paste: Bool) -> Void)?
    @ObservationIgnored var onDismiss: (() -> Void)?

    /// One screen of cards is a few dozen; this is generous enough that
    /// scrolling never waits and small enough to rebuild in a frame.
    static let pageLimit = 500

    init(clips: ClipRepository, blobs: BlobStore) {
        self.clips = clips
        self.blobs = blobs
    }

    // MARK: - Lifetime

    /// Called when the board appears. Nothing observes or ticks while it is
    /// hidden, which for a menu-bar app is nearly all of the time.
    func start() {
        now = Date()
        previewedID = nil

        // Every opening starts on the newest clip. The board is transient — it
        // is summoned to grab one thing and dismissed — so leaving the keyboard
        // wherever it was left five minutes ago means the very first Return
        // pastes something the user was not looking at.
        focusedID = nil

        // Synchronously first, so the board paints with content on the frame it
        // appears rather than flashing an empty strip and filling in a beat
        // later. The observation below only ever *changes* what is already there.
        reload()

        if observationTask == nil {
            let observation = clips.observePage(limit: Self.pageLimit)
            observationTask = Task { [weak self] in
                do {
                    for try await records in observation {
                        self?.apply(records)
                    }
                } catch {
                    Log.store.error("the clip feed stopped: \(error, privacy: .public)")
                }
            }
        }

        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                self?.tick()
            }
        }
    }

    /// One synchronous fetch. Cheap — an indexed query with a limit.
    func reload() {
        do {
            apply(try clips.page(limit: Self.pageLimit))
        } catch {
            Log.store.error("could not read clips: \(error, privacy: .public)")
        }
    }

    func stop() {
        clockTask?.cancel()
        clockTask = nil
        previewedID = nil
    }

    private func apply(_ records: [ClipRecord]) {
        self.records = records
        sections = ClipSectionBuilder.sections(from: records, now: now)
        isLoaded = true

        AppIconCache.shared.prewarm(records.compactMap(\.sourceBundleID))

        // Keep the keyboard somewhere sensible when the list changes underneath
        // it — a clip arriving or being deleted should not lose the user's place.
        if focusedID == nil || !cards.contains(where: { $0.id == focusedID }) {
            focusedID = cards.first?.id
        }
    }

    private func tick() {
        now = Date()
        for sectionIndex in sections.indices {
            for cardIndex in sections[sectionIndex].cards.indices {
                let created = sections[sectionIndex].cards[cardIndex].createdAt
                sections[sectionIndex].cards[cardIndex].timestamp =
                    RelativeTime.string(for: created, relativeTo: now)
            }
        }
    }

    // MARK: - Focus

    var cards: [ClipCardModel] {
        sections.flatMap(\.cards)
    }

    var focusedCard: ClipCardModel? {
        cards.first { $0.id == focusedID }
    }

    private var focusedIndex: Int? {
        cards.firstIndex { $0.id == focusedID }
    }

    func moveFocus(by offset: Int) {
        let cards = cards
        guard !cards.isEmpty else { return }
        let current = focusedIndex ?? 0
        // Clamped rather than wrapped: arriving back at the newest clip after
        // pressing → once too often is disorienting when nothing else moved.
        focusedID = cards[min(max(current + offset, 0), cards.count - 1)].id
    }

    func focusFirst() {
        focusedID = cards.first?.id
    }

    func focusLast() {
        focusedID = cards.last?.id
    }

    /// ⌥← and ⌥→: jump a whole day at a time.
    ///
    /// Going back lands on the start of the *current* day before it leaves for
    /// the previous one, which is what jumping by group means everywhere else on
    /// the platform. Going forward past the last day lands on the oldest clip
    /// rather than bouncing backwards to the head of the day already in view.
    func moveFocusBySection(_ offset: Int) {
        guard !sections.isEmpty else { return }
        let current = sections.firstIndex { section in
            section.cards.contains { $0.id == focusedID }
        } ?? 0

        if offset < 0 {
            if focusedID != sections[current].cards.first?.id {
                focusedID = sections[current].cards.first?.id
                return
            }
            guard current > 0 else { return }
            focusedID = sections[current - 1].cards.first?.id
            return
        }

        guard current + 1 < sections.count else {
            focusedID = sections[current].cards.last?.id
            return
        }
        focusedID = sections[current + 1].cards.first?.id
    }

    // MARK: - Actions

    func paste() {
        activate(focusedCard, paste: true)
    }

    func copyWithoutPasting() {
        activate(focusedCard, paste: false)
    }

    /// ⌘1 through ⌘9, counted from the newest clip.
    func paste(at index: Int) {
        let cards = cards
        guard cards.indices.contains(index) else { return }
        activate(cards[index], paste: true)
    }

    private func activate(_ card: ClipCardModel?, paste: Bool) {
        guard
            let card,
            let record = records.first(where: { $0.id == card.id })
        else { return }
        onActivate?(record, paste)
    }

    func deleteFocused() {
        guard let card = focusedCard, let index = focusedIndex else { return }

        // Choose where the keyboard lands before the row disappears, so focus
        // moves to the neighbour rather than snapping back to the newest clip.
        let cards = cards
        let successor = cards.indices.contains(index + 1)
            ? cards[index + 1].id
            : (index > 0 ? cards[index - 1].id : nil)

        do {
            _ = try clips.delete(ids: [card.id])
            focusedID = successor
            if previewedID == card.id { previewedID = nil }
        } catch {
            Log.store.error("could not delete a clip: \(error, privacy: .public)")
            NSSound.beep()
        }
    }

    // MARK: - Content, for the large preview

    /// The whole clip, not the 240-character excerpt a card shows.
    ///
    /// Only the preview overlay asks for this, and only for one clip at a time,
    /// which is why reading a blob here is affordable where doing it per card
    /// would not be.
    func fullText(for card: ClipCardModel) -> String {
        guard let record = records.first(where: { $0.id == card.id }) else { return card.preview }
        if let inline = record.inlineText { return inline }
        guard
            let key = record.blobKey,
            let data = try? blobs.data(for: key),
            let text = String(data: data, encoding: .utf8)
        else { return card.preview }
        return text
    }

    /// The original image rather than its thumbnail, so a preview blown up to
    /// most of the screen is sharp.
    func imageData(for card: ClipCardModel) -> Data? {
        guard
            let record = records.first(where: { $0.id == card.id }),
            let key = record.blobKey
        else { return nil }
        return try? blobs.data(for: key)
    }

    // MARK: - Preview

    var previewedCard: ClipCardModel? {
        cards.first { $0.id == previewedID }
    }

    func togglePreview() {
        previewedID = previewedID == nil ? focusedID : nil
    }

    /// Escape closes the preview if one is open, and the board otherwise — one
    /// key that always means "back", never "quit out of two things at once".
    func escape() {
        if previewedID != nil {
            previewedID = nil
        } else {
            onDismiss?()
        }
    }
}
