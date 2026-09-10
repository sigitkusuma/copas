import Foundation
import Testing

@testable import Copas

struct PinningTests {

    let repository: ClipRepository

    init() throws {
        repository = ClipRepository(database: try AppDatabase.inMemory())
    }

    static let epoch = Date(timeIntervalSince1970: 1_760_000_000)

    private func at(_ offset: TimeInterval) -> Date {
        Self.epoch.addingTimeInterval(offset)
    }

    private func text(
        _ string: String,
        at date: Date,
        isPinned: Bool = false,
        id: String = UUID().uuidString
    ) -> ClipRecord {
        ClipRecord.text(string, at: date, id: id, isPinned: isPinned) { ContentHash.hex(of: $0) }
    }

    @Test func clipDefaultsToUnpinned() throws {
        let record = text("hello", at: at(0))
        #expect(!record.isPinned)
    }

    @Test func setPinnedUpdatesDatabase() throws {
        let record = text("pin me", at: at(0))
        try repository.insert(record)

        let pinned = try repository.setPinned(true, for: record.id)
        #expect(pinned?.isPinned == true)

        let fetched = try repository.record(id: record.id)
        #expect(fetched?.isPinned == true)

        let unpinned = try repository.setPinned(false, for: record.id)
        #expect(unpinned?.isPinned == false)

        let fetchedAgain = try repository.record(id: record.id)
        #expect(fetchedAgain?.isPinned == false)
    }

    @Test func pruneRetainsPinnedClipsPastCountLimit() throws {
        // Insert 3 clips: 1 pinned older clip, 2 unpinned newer clips
        let pinnedOld = text("important template", at: at(0), isPinned: true)
        let unpinned1 = text("unpinned 1", at: at(10))
        let unpinned2 = text("unpinned 2", at: at(20))

        try repository.insert(pinnedOld)
        try repository.insert(unpinned1)
        try repository.insert(unpinned2)

        // Prune to maximumCount: 1. Normally pinnedOld would be dropped if it weren't protected.
        let removed = try repository.prune(RetentionPolicy(maximumCount: 1), now: at(30))

        // unpinned1 should be dropped, leaving unpinned2 and pinnedOld.
        #expect(removed.contains { $0.id == unpinned1.id })
        #expect(!removed.contains { $0.id == pinnedOld.id })

        let remaining = try repository.page(limit: 10)
        #expect(remaining.contains { $0.id == pinnedOld.id })
        #expect(remaining.contains { $0.id == unpinned2.id })
    }

    @Test func pruneRetainsPinnedClipsPastAgeLimit() throws {
        let pinnedAncient = text("ancient snippet", at: at(0), isPinned: true)
        let unpinnedAncient = text("ancient temporary", at: at(0), isPinned: false)

        try repository.insert(pinnedAncient)
        try repository.insert(unpinnedAncient)

        // Prune older than 50 seconds from at(100)
        let removed = try repository.prune(RetentionPolicy(maximumAge: 50), now: at(100))

        #expect(removed.contains { $0.id == unpinnedAncient.id })
        #expect(!removed.contains { $0.id == pinnedAncient.id })

        let remaining = try repository.page(limit: 10)
        #expect(remaining.contains { $0.id == pinnedAncient.id })
        #expect(!remaining.contains { $0.id == unpinnedAncient.id })
    }

    @Test func pinnedClipsAreOrderedAtTheTop() throws {
        let oldPinned = text("pinned old", at: at(0), isPinned: true)
        let newestUnpinned = text("unpinned new", at: at(100), isPinned: false)
        let newestPinned = text("pinned new", at: at(50), isPinned: true)

        try repository.insert(oldPinned)
        try repository.insert(newestUnpinned)
        try repository.insert(newestPinned)

        let page = try repository.page(limit: 10)
        #expect(page.count == 3)
        // Pinned clips first, ordered by created_at DESC
        #expect(page[0].id == newestPinned.id)
        #expect(page[1].id == oldPinned.id)
        // Unpinned clips follow
        #expect(page[2].id == newestUnpinned.id)
    }

    @Test func searchQueryParsesIsPinnedTokens() {
        let queryPinned = SearchQuery("is:pinned hello")
        #expect(queryPinned.isPinned == true)
        #expect(queryPinned.terms == ["hello"])

        let queryStar = SearchQuery("is:starred")
        #expect(queryStar.isPinned == true)
        #expect(queryStar.terms.isEmpty)

        let queryUnpinned = SearchQuery("is:unpinned")
        #expect(queryUnpinned.isPinned == false)
    }
}
