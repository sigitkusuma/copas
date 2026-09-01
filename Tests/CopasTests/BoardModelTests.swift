import Foundation
import Testing

@testable import Copas

@MainActor
final class BoardModelTests {

    let root: URL
    let clips: ClipRepository
    let model: BoardModel

    static let now = Date(timeIntervalSince1970: 1_760_000_000)

    init() throws {
        root = try Fixtures.temporaryDirectory("board")
        clips = ClipRepository(database: try AppDatabase.inMemory())
        model = BoardModel(clips: clips, blobs: BlobStore(root: root.appendingPathComponent("blobs")))
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Inserts newest-last, so `previews` below read in the order they appear.
    @discardableResult
    private func insert(_ previews: [String], daysAgo: Int = 0) throws -> [String] {
        var ids: [String] = []
        for (index, preview) in previews.enumerated() {
            let date = Calendar.current
                .date(byAdding: .day, value: -daysAgo, to: Self.now)!
                .addingTimeInterval(TimeInterval(-index * 60))
            let record = ClipRecord.text(preview, at: date) { _ in "" }
            _ = try clips.insert(record)
            ids.append(record.id)
        }
        return ids
    }

    // MARK: - Loading

    @Test func loadingBuildsSectionsAndFocusesTheNewest() throws {
        try insert(["newest", "older"])
        model.reload()

        #expect(model.cards.map(\.preview) == ["newest", "older"])
        #expect(model.focusedID == model.cards.first?.id)
        #expect(!model.isEmpty)
    }

    @Test func anEmptyHistoryIsReportedOnlyAfterLoading() {
        #expect(!model.isEmpty, "must not claim to be empty before it has looked")
        model.reload()
        #expect(model.isEmpty)
    }

    /// The board is summoned to grab one thing and dismissed. Leaving focus
    /// wherever it was left five minutes ago means the first Return pastes
    /// something the user was not looking at.
    @Test func openingTheBoardStartsOnTheNewestClipAgain() throws {
        try insert(["newest", "middle", "oldest"])
        model.start()
        model.focusLast()
        model.stop()

        model.start()
        #expect(model.focusedCard?.preview == "newest")
        model.stop()
    }

    // MARK: - Focus

    @Test func arrowsMoveThroughEveryCardAcrossSections() throws {
        try insert(["a", "b"], daysAgo: 0)
        try insert(["c"], daysAgo: 1)
        model.reload()

        model.moveFocus(by: 1)
        #expect(model.focusedCard?.preview == "b")
        model.moveFocus(by: 1)
        #expect(model.focusedCard?.preview == "c", "focus must cross a day boundary")
    }

    /// Clamped rather than wrapped: arriving back at the newest clip after
    /// pressing → once too often is disorienting when nothing else moved.
    @Test func focusStopsAtTheEndsRatherThanWrapping() throws {
        try insert(["a", "b"])
        model.reload()

        model.moveFocus(by: -5)
        #expect(model.focusedCard?.preview == "a")
        model.moveFocus(by: 5)
        #expect(model.focusedCard?.preview == "b")
    }

    @Test func homeAndEndJumpToTheEnds() throws {
        try insert(["a", "b", "c"])
        model.reload()

        model.focusLast()
        #expect(model.focusedCard?.preview == "c")
        model.focusFirst()
        #expect(model.focusedCard?.preview == "a")
    }

    /// Scrolling by hand must not drag the selection with it, which is why the
    /// scroll anchor is a separate property that focus writes into one way.
    @Test func movingFocusPullsTheScrollAnchorAlong() throws {
        try insert(["a", "b"])
        model.reload()
        model.moveFocus(by: 1)

        #expect(model.scrollAnchorID == model.focusedID)

        model.scrollAnchorID = "something the user scrolled to"
        #expect(model.focusedCard?.preview == "b", "scrolling must not move focus")
    }

    // MARK: - Section jumps

    @Test func optionArrowGoesToTheStartOfTheDayBeforeLeavingIt() throws {
        try insert(["a", "b", "c"], daysAgo: 0)
        try insert(["d", "e"], daysAgo: 1)
        model.reload()
        model.focusLast()

        model.moveFocusBySection(-1)
        #expect(model.focusedCard?.preview == "d", "first to the head of the day in view")

        model.moveFocusBySection(-1)
        #expect(model.focusedCard?.preview == "a", "then to the head of the previous day")
    }

    /// Already at the head of a day, so there is nothing to do but leave it.
    @Test func optionArrowLeavesADayImmediatelyWhenAlreadyAtItsHead() throws {
        try insert(["a", "b"], daysAgo: 0)
        try insert(["c"], daysAgo: 1)
        model.reload()
        model.focusLast()

        model.moveFocusBySection(-1)
        #expect(model.focusedCard?.preview == "a")
    }

    @Test func optionArrowForwardLandsOnTheNextDay() throws {
        try insert(["a", "b"], daysAgo: 0)
        try insert(["c", "d"], daysAgo: 1)
        model.reload()

        model.moveFocusBySection(1)
        #expect(model.focusedCard?.preview == "c")
    }

    /// Jumping forward from the last day should reach the oldest clip, not bounce
    /// backwards to the head of the day already in view.
    @Test func jumpingPastTheLastDayLandsOnTheOldestClip() throws {
        try insert(["a"], daysAgo: 0)
        try insert(["b", "c"], daysAgo: 1)
        model.reload()
        model.moveFocusBySection(1)

        model.moveFocusBySection(1)
        #expect(model.focusedCard?.preview == "c")
    }

    // MARK: - Actions

    @Test func returnHandsTheRecordUpToBePasted() throws {
        try insert(["a", "b"])
        model.reload()
        model.moveFocus(by: 1)

        var activated: (ClipRecord, Bool)?
        model.onActivate = { activated = ($0, $1) }

        model.paste()
        #expect(activated?.0.preview == "b")
        #expect(activated?.1 == true)

        model.copyWithoutPasting()
        #expect(activated?.1 == false)
    }

    @Test func commandDigitPastesWithoutMovingFocusFirst() throws {
        try insert(["a", "b", "c"])
        model.reload()

        var activated: ClipRecord?
        model.onActivate = { record, _ in activated = record }

        model.paste(at: 2)
        #expect(activated?.preview == "c")
        #expect(model.focusedCard?.preview == "a", "⌘3 pastes the third card, it does not select it")
    }

    @Test func aDigitPastTheEndDoesNothing() throws {
        try insert(["a"])
        model.reload()

        var activated = false
        model.onActivate = { _, _ in activated = true }

        model.paste(at: 8)
        #expect(!activated)
    }

    /// Deleting should leave the keyboard on the neighbour, not snap it back to
    /// the newest clip — otherwise clearing a run of clips means re-navigating
    /// after every single one.
    @Test func deletingMovesFocusToTheNextCard() throws {
        try insert(["a", "b", "c"])
        model.reload()
        model.moveFocus(by: 1)

        model.deleteFocused()
        model.reload()

        #expect(model.cards.map(\.preview) == ["a", "c"])
        #expect(model.focusedCard?.preview == "c")
    }

    @Test func deletingTheOldestFallsBackToTheOneBefore() throws {
        try insert(["a", "b"])
        model.reload()
        model.focusLast()

        model.deleteFocused()
        model.reload()

        #expect(model.focusedCard?.preview == "a")
    }

    @Test func deletingTheLastClipLeavesNothingFocused() throws {
        try insert(["only"])
        model.reload()

        model.deleteFocused()
        model.reload()

        #expect(model.focusedID == nil)
        #expect(model.isEmpty)
    }

    // MARK: - Preview and escape

    @Test func spaceOpensAndClosesTheLargePreview() throws {
        try insert(["a"])
        model.reload()

        model.togglePreview()
        #expect(model.previewedCard?.preview == "a")

        model.togglePreview()
        #expect(model.previewedCard == nil)
    }

    /// One key that always means "back", never "close two things at once".
    @Test func escapeClosesThePreviewBeforeTheBoard() throws {
        try insert(["a"])
        model.reload()

        var dismissed = false
        model.onDismiss = { dismissed = true }

        model.togglePreview()
        model.escape()
        #expect(model.previewedCard == nil)
        #expect(!dismissed, "the first escape closes the preview only")

        model.escape()
        #expect(dismissed)
    }

    @Test func deletingTheClipBeingPreviewedClosesThePreview() throws {
        try insert(["a", "b"])
        model.reload()
        model.togglePreview()

        model.deleteFocused()
        #expect(model.previewedCard == nil)
    }
}
