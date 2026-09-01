import Foundation
import Testing

@testable import Copas

/// Guards the numbers that decide whether the board feels instant.
///
/// Bounds are roughly ten times what this measured on a developer machine —
/// page 2.2 ms, search 2.5 ms, building 500 cards 11.6 ms, pruning 1,500 rows
/// 17 ms. Loose enough to survive a busy machine, tight enough to catch a
/// change that makes something an order of magnitude slower. A bound that
/// policed milliseconds would flake and then be deleted, which is worse than
/// having none.
///
/// Card building is the number to watch: it is the only one on the main thread,
/// and at 11.6 ms for a full page it is already most of a frame. The search
/// debounce is what keeps that to once per query rather than once per keystroke.
@MainActor
final class PerformanceTests {

    let root: URL
    let clips: ClipRepository
    let blobs: BlobStore

    static let clipCount = 2_000
    static let epoch = Date(timeIntervalSince1970: 1_760_000_000)

    init() throws {
        root = try Fixtures.temporaryDirectory("perf")
        clips = ClipRepository(database: try AppDatabase.inMemory())
        blobs = BlobStore(root: root.appendingPathComponent("blobs"))
        try seed()
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// A history shaped like a real one: mostly short text, some code, a few
    /// long clips, spread over a fortnight so the board has day sections to
    /// build rather than one enormous run.
    private func seed() throws {
        var records: [ClipRecord] = []
        records.reserveCapacity(Self.clipCount)

        for index in 0..<Self.clipCount {
            let text: String
            switch index % 10 {
            case 0:
                text = "func handler\(index)(_ value: Int) -> Bool { value > \(index) }"
            case 1:
                text = String(repeating: "long form clip \(index). ", count: 60)
            default:
                text = "clipboard entry number \(index) about invoices and receipts"
            }

            records.append(ClipRecord.text(
                text,
                source: SourceApp(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
                at: Self.epoch.addingTimeInterval(TimeInterval(-index * 600)),
                id: "clip-\(index)"
            ) { _ in ContentHash.hex(of: "blob-\(index)") })
        }

        let summary = try clips.importRecords(records)
        #expect(summary.imported == Self.clipCount)
    }

    private func duration(_ work: () throws -> Void) rethrows -> Duration {
        let start = ContinuousClock.now
        try work()
        return ContinuousClock.now - start
    }

    @Test func aFullPageIsFetchedInWellUnderAFrame() throws {
        var page: [ClipRecord] = []
        let elapsed = try duration {
            page = try clips.page(limit: BoardModel.pageLimit)
        }

        #expect(page.count == BoardModel.pageLimit)
        #expect(elapsed < .milliseconds(50), "a page of \(page.count) took \(elapsed)")
    }

    /// The whole point of an index. A search that scanned two thousand rows
    /// would still look fast here and fall over at twenty thousand.
    @Test func searchingTheWholeHistoryIsFast() throws {
        var hits: [ClipRecord] = []
        let elapsed = try duration {
            hits = try clips.page(matching: .text("invoices"), limit: BoardModel.pageLimit)
        }

        #expect(!hits.isEmpty)
        #expect(elapsed < .milliseconds(50), "search took \(elapsed)")
    }

    /// Counting is separate from paging and runs on every keystroke, so it has
    /// its own budget.
    @Test func countingMatchesIsFast() throws {
        var total = 0
        let elapsed = try duration {
            total = try clips.count(matching: .text("invoices"))
        }

        #expect(total > 0)
        #expect(elapsed < .milliseconds(25), "counting took \(elapsed)")
    }

    /// Runs on the main thread every time the board opens and every time the
    /// query changes, so it is the one that shows up as a stutter.
    @Test func buildingCardsForAFullPageIsFast() throws {
        let records = try clips.page(limit: BoardModel.pageLimit)
        var sections: [ClipSection] = []

        let elapsed = duration {
            sections = ClipSectionBuilder.sections(from: records, now: Self.epoch, terms: ["invoices"])
        }

        #expect(sections.count > 1, "a fortnight of clips should produce day sections")
        #expect(sections.reduce(0) { $0 + $1.cards.count } == records.count)
        #expect(elapsed < .milliseconds(100), "building \(records.count) cards took \(elapsed)")
    }

    /// The clock tick rewrites every visible card's timestamp. It happens while
    /// the board is open, so it competes with scrolling.
    @Test func retimingEveryCardIsCheap() throws {
        let records = try clips.page(limit: BoardModel.pageLimit)
        let cards = ClipSectionBuilder.sections(from: records, now: Self.epoch).flatMap(\.cards)
        let later = Self.epoch.addingTimeInterval(120)

        let elapsed = duration {
            for card in cards {
                _ = RelativeTime.string(for: card.createdAt, relativeTo: later)
            }
        }

        #expect(elapsed < .milliseconds(15), "retiming \(cards.count) cards took \(elapsed)")
    }

    /// Every card asks this once. A heuristic that read the whole clip would be
    /// invisible on one card and a stall on five hundred.
    @Test func theCodeHeuristicIsCheapEnoughForEveryCard() throws {
        let records = try clips.page(limit: BoardModel.pageLimit)

        let elapsed = duration {
            for record in records {
                _ = CodeHeuristic.looksLikeCode(record.preview)
            }
        }

        #expect(elapsed < .milliseconds(40), "\(records.count) heuristics took \(elapsed)")
    }

    @Test func trimmingAFullHistoryIsFast() throws {
        var removed: [ClipRecord] = []
        let elapsed = try duration {
            removed = try clips.prune(RetentionPolicy(maximumCount: 500))
        }

        #expect(removed.count == Self.clipCount - 500)
        #expect(elapsed < .milliseconds(200), "pruning took \(elapsed)")
    }
}
