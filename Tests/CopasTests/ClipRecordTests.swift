import Foundation
import Testing

@testable import Copas

struct ClipRecordTests {

    /// Line structure is what tells you at a glance which snippet you are
    /// looking at, so a preview keeps it. Only noise is normalised.
    @Test func previewKeepsLinesAndIndentation() {
        let code = "func add() {\n    return 1\n}"
        #expect(ClipRecord.makePreview(from: code) == code)
    }

    @Test func previewTrimsTheEdgesAndCollapsesBlankRuns() {
        #expect(ClipRecord.makePreview(from: "  hello  \n\n\n\n\nworld  ") == "hello\n\nworld")
    }

    @Test func previewNormalisesWindowsLineEndings() {
        #expect(ClipRecord.makePreview(from: "one\r\ntwo") == "one\ntwo")
    }

    /// A run of alignment spaces should not be able to spend the whole budget.
    @Test func previewBoundsARunOfSpaces() {
        let padded = "a" + String(repeating: " ", count: 200) + "b"
        #expect(ClipRecord.makePreview(from: padded) == "a" + String(repeating: " ", count: 8) + "b")
    }

    @Test func previewStopsAtTheLimit() {
        let long = String(repeating: "a", count: 5_000)
        #expect(ClipRecord.makePreview(from: long).count == ClipRecord.previewLimit)
    }

    @Test func previewOfEmptyTextIsEmpty() {
        #expect(ClipRecord.makePreview(from: "   \n\t ").isEmpty)
    }

    @Test func textUnderTheLimitStaysInTheRow() {
        let record = ClipRecord.text("hello") { _ in
            Issue.record("small text should never reach the blob store")
            return ""
        }
        #expect(record.isInline)
        #expect(record.inlineText == "hello")
        #expect(record.blobKey == nil)
        #expect(record.charCount == 5)
        #expect(record.byteSize == 5)
    }

    /// The rule that replaced the old truncating path: oversized text is moved,
    /// never shortened.
    @Test func textOverTheLimitGoesToABlobIntact() {
        let long = String(repeating: "x", count: ClipRecord.inlineByteLimit + 1)
        var stored: Data?
        let record = ClipRecord.text(long) { data in
            stored = data
            return ContentHash.hex(of: data)
        }
        #expect(!record.isInline)
        #expect(record.inlineText == nil)
        #expect(record.blobKey == ContentHash.hex(of: Data(long.utf8)))
        #expect(stored?.count == ClipRecord.inlineByteLimit + 1)
        #expect(record.charCount == long.count)
    }

    @Test func inlineBoundaryIsMeasuredInBytesNotCharacters() {
        // Four bytes each, so this is exactly at the limit despite being a
        // quarter as many characters.
        let emoji = String(repeating: "🙂", count: ClipRecord.inlineByteLimit / 4)
        let record = ClipRecord.text(emoji) { _ in "" }
        #expect(record.isInline)
        #expect(record.byteSize == ClipRecord.inlineByteLimit)
    }

    /// The whole reason for using SHA-256 rather than `hashValue`: this number is
    /// the same in every process, so a dedupe index survives a relaunch.
    @Test func contentHashIsTheRealDigest() {
        #expect(ContentHash.hex(of: "hello")
            == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    @Test func onlyLowercaseSixtyFourCharacterHexIsAValidKey() {
        #expect(ContentHash.isValidKey(ContentHash.hex(of: "hello")))
        #expect(!ContentHash.isValidKey("2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824"))
        #expect(!ContentHash.isValidKey("../../../etc/passwd"))
        #expect(!ContentHash.isValidKey(""))
    }
}
