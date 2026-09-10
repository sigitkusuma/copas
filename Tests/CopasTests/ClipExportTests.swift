import Foundation
import Testing

@testable import Copas

struct ClipExportTests {

    @Test func sanitizeFilenameRemovesInvalidCharacters() {
        let input = "Hello / World : File * Name ?"
        let cleaned = ClipExportUtility.sanitizeFilename(input)
        #expect(!cleaned.contains("/"))
        #expect(!cleaned.contains(":"))
        #expect(!cleaned.contains("*"))
        #expect(!cleaned.contains("?"))
    }

    @Test func sanitizeFilenameCapsLength() {
        let longString = String(repeating: "abcdefghij", count: 10)
        let cleaned = ClipExportUtility.sanitizeFilename(longString)
        #expect(cleaned.count <= 32)
    }

    @Test func sanitizeFilenameFallbackOnEmpty() {
        let empty = "   /// ::: ??? "
        let cleaned = ClipExportUtility.sanitizeFilename(empty, fallback: "custom-fallback")
        #expect(cleaned == "custom-fallback")
    }

    @Test func suggestedFilenameForJSON() {
        let json = "{\"name\": \"copas\", \"version\": 1}"
        let name = ClipExportUtility.suggestedFilename(for: json)
        #expect(name.hasSuffix(".json"))
    }

    @Test func suggestedFilenameForURL() {
        let url = "https://github.com/sigitkusuma/copas"
        let name = ClipExportUtility.suggestedFilename(for: url)
        #expect(name.hasSuffix(".md"))
    }

    @Test func suggestedFilenameForPlainText() {
        let text = "Just some ordinary notes"
        let name = ClipExportUtility.suggestedFilename(for: text)
        #expect(name.hasSuffix(".txt"))
    }
}
