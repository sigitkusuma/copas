import Foundation
import Testing

@testable import Copas

struct SmartFilterTests {

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

    private func image(
        seed: String,
        at date: Date,
        isPinned: Bool = false,
        id: String = UUID().uuidString
    ) -> ClipRecord {
        ClipRecord.image(
            blobKey: ContentHash.hex(of: seed),
            thumbKey: ContentHash.hex(of: seed) + ".jpg",
            contentHash: ContentHash.hex(of: seed),
            byteSize: 1_024,
            pixelWidth: 800,
            pixelHeight: 600,
            at: date,
            id: id,
            isPinned: isPinned
        )
    }

    @Test func filterByPinned() throws {
        let pinned = text("pinned text", at: at(10), isPinned: true)
        let unpinned = text("unpinned text", at: at(20), isPinned: false)

        try repository.insert(pinned)
        try repository.insert(unpinned)

        let query = ClipQuery(smartFilter: .pinned)
        let results = try repository.page(matching: query, limit: 10)

        #expect(results.count == 1)
        #expect(results.first?.id == pinned.id)
    }

    @Test func filterByImages() throws {
        let img = image(seed: "img1", at: at(10))
        let txt = text("plain text", at: at(20))

        try repository.insert(img)
        try repository.insert(txt)

        let query = ClipQuery(smartFilter: .images)
        let results = try repository.page(matching: query, limit: 10)

        #expect(results.count == 1)
        #expect(results.first?.id == img.id)
    }

    @Test func filterByLinks() throws {
        let link1 = text("Visit https://apple.com for more", at: at(10))
        let link2 = text("http://example.com", at: at(20))
        let normal = text("Just some random text", at: at(30))

        try repository.insert(link1)
        try repository.insert(link2)
        try repository.insert(normal)

        let query = ClipQuery(smartFilter: .links)
        let results = try repository.page(matching: query, limit: 10)

        #expect(results.count == 2)
        #expect(results.contains { $0.id == link1.id })
        #expect(results.contains { $0.id == link2.id })
        #expect(!results.contains { $0.id == normal.id })
    }

    @Test func filterByColors() throws {
        let hex6 = text("#FF5733", at: at(10))
        let hex3 = text("#fff", at: at(15))
        let rgb = text("rgb(255, 0, 0)", at: at(18))
        let markdownHeading = text("# System Prompt — Overview", at: at(20))
        let markdownSubheading = text("## Flowchart", at: at(22))
        let nonColor = text("This is #notacolor really", at: at(25))

        try repository.insert(hex6)
        try repository.insert(hex3)
        try repository.insert(rgb)
        try repository.insert(markdownHeading)
        try repository.insert(markdownSubheading)
        try repository.insert(nonColor)

        let query = ClipQuery(smartFilter: .colors)
        let results = try repository.page(matching: query, limit: 10)

        #expect(results.count == 3)
        #expect(results.contains { $0.id == hex6.id })
        #expect(results.contains { $0.id == hex3.id })
        #expect(results.contains { $0.id == rgb.id })
        #expect(!results.contains { $0.id == markdownHeading.id })
        #expect(!results.contains { $0.id == markdownSubheading.id })
        #expect(!results.contains { $0.id == nonColor.id })
    }
}
