import Foundation
import Testing

@testable import Copas

final class BlobStoreTests {

    let root: URL
    let store: BlobStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("copas-blobs-\(UUID().uuidString)", isDirectory: true)
        store = BlobStore(root: root)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    @Test func writingReturnsTheContentHashAndReadsBack() throws {
        let data = Data("hello".utf8)
        let key = try store.write(data)

        #expect(key == ContentHash.hex(of: data))
        #expect(try store.data(for: key) == data)
        #expect(store.contains(key))
    }

    @Test func writingTheSameBytesTwiceIsOneFile() throws {
        let data = Data("hello".utf8)
        let first = try store.write(data)
        let second = try store.write(data)

        #expect(first == second)
        #expect(try ContentAddressedDirectory(root: root).filenames().count == 1)
    }

    /// The sharded layout is the reason a key is never used as a raw path.
    @Test func filesLandInATwoCharacterShard() throws {
        let key = try store.write(Data("hello".utf8))
        let url = try store.url(for: key)
        #expect(url.deletingLastPathComponent().lastPathComponent == String(key.prefix(2)))
    }

    @Test func readingAnAbsentKeyReportsItMissing() throws {
        let key = ContentHash.hex(of: "never written")
        #expect(throws: BlobStoreError.missing(key)) {
            _ = try store.data(for: key)
        }
    }

    /// Keys can arrive from an imported file rather than from us, and a key is a
    /// path component. Anything that is not a digest is refused outright.
    @Test func aKeyThatIsNotADigestIsRefused() {
        #expect(throws: BlobStoreError.self) {
            _ = try store.data(for: "../../../etc/passwd")
        }
        #expect(!store.contains("../../../etc/passwd"))
    }

    @Test func garbageCollectionRemovesOrphansAndKeepsTheRest() throws {
        let kept = try store.write(Data("kept".utf8))
        _ = try store.write(Data("orphan one".utf8))
        _ = try store.write(Data("orphan two".utf8))

        let removed = try store.collectGarbage(keeping: [kept])

        #expect(removed == 2)
        #expect(store.contains(kept))
        #expect(try ContentAddressedDirectory(root: root).filenames() == [kept])
    }

    @Test func garbageCollectionOnAStoreThatWasNeverWrittenToIsHarmless() throws {
        #expect(try store.collectGarbage(keeping: []) == 0)
    }
}
