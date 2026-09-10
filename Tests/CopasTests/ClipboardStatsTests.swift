import Foundation
import Testing

@testable import Copas

struct ClipboardStatsTests {

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
        source: SourceApp = SourceApp(),
        at date: Date,
        isPinned: Bool = false,
        id: String = UUID().uuidString
    ) -> ClipRecord {
        ClipRecord.text(string, source: source, at: date, id: id, isPinned: isPinned) { ContentHash.hex(of: $0) }
    }

    private func image(
        seed: String,
        source: SourceApp = SourceApp(),
        at date: Date,
        isPinned: Bool = false,
        id: String = UUID().uuidString
    ) -> ClipRecord {
        ClipRecord.image(
            blobKey: ContentHash.hex(of: seed),
            thumbKey: ContentHash.hex(of: seed) + ".jpg",
            contentHash: ContentHash.hex(of: seed),
            byteSize: 2_048,
            pixelWidth: 800,
            pixelHeight: 600,
            source: source,
            at: date,
            id: id,
            isPinned: isPinned
        )
    }

    @Test func statisticsOnEmptyDatabase() throws {
        let stats = try repository.statistics(now: at(0))
        #expect(stats.totalClips == 0)
        #expect(stats.textClips == 0)
        #expect(stats.imageClips == 0)
        #expect(stats.pinnedClips == 0)
        #expect(stats.clipsToday == 0)
        #expect(stats.clipsThisWeek == 0)
        #expect(stats.topApps.isEmpty)
    }

    @Test func statisticsCalculatesCountsAndApps() throws {
        let safari = SourceApp(bundleID: "com.apple.Safari", name: "Safari")
        let xcode = SourceApp(bundleID: "com.apple.dt.Xcode", name: "Xcode")

        let now = at(100_000)
        // Insert 2 texts from Safari, 1 pinned
        try repository.insert(text("URL 1", source: safari, at: now, isPinned: true))
        try repository.insert(text("URL 2", source: safari, at: now.addingTimeInterval(-10)))

        // Insert 1 text from Xcode
        try repository.insert(text("let x = 10", source: xcode, at: now.addingTimeInterval(-20)))

        // Insert 1 image from Safari
        try repository.insert(image(seed: "img", source: safari, at: now.addingTimeInterval(-30)))

        let stats = try repository.statistics(now: now)
        #expect(stats.totalClips == 4)
        #expect(stats.textClips == 3)
        #expect(stats.imageClips == 1)
        #expect(stats.pinnedClips == 1)
        #expect(stats.clipsToday == 4)
        #expect(stats.clipsThisWeek == 4)

        // Top apps
        #expect(stats.topApps.count == 2)
        #expect(stats.topApps[0].name == "Safari")
        #expect(stats.topApps[0].count == 3)
        #expect(stats.topApps[1].name == "Xcode")
        #expect(stats.topApps[1].count == 1)
    }
}
