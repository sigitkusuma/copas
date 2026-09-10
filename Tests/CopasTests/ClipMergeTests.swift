import Foundation
import Testing

@testable import Copas

struct ClipMergeTests {

    @Test func mergeWithDoubleNewline() {
        let clips = ["First paragraph", "Second paragraph"]
        let merged = ClipMergeUtility.merge(clips, delimiter: .doubleNewline)
        #expect(merged == "First paragraph\n\nSecond paragraph")
    }

    @Test func mergeWithSingleNewline() {
        let clips = ["Item 1", "Item 2", "Item 3"]
        let merged = ClipMergeUtility.merge(clips, delimiter: .singleNewline)
        #expect(merged == "Item 1\nItem 2\nItem 3")
    }

    @Test func mergeWithCommas() {
        let clips = ["apple", "banana", "cherry"]
        let merged = ClipMergeUtility.merge(clips, delimiter: .comma)
        #expect(merged == "apple, banana, cherry")
    }

    @Test func mergeWithTabs() {
        let clips = ["col1", "col2", "col3"]
        let merged = ClipMergeUtility.merge(clips, delimiter: .tab)
        #expect(merged == "col1\tcol2\tcol3")
    }

    @Test func mergeWithSpaces() {
        let clips = ["quick", "brown", "fox"]
        let merged = ClipMergeUtility.merge(clips, delimiter: .space)
        #expect(merged == "quick brown fox")
    }

    @Test func mergeIgnoresEmptyAndWhitespaceOnlyClips() {
        let clips = ["First", "   ", "", "\n\n", "Second"]
        let merged = ClipMergeUtility.merge(clips, delimiter: .comma)
        #expect(merged == "First, Second")
    }

    @Test func mergeSingleClipReturnsTrimmedContent() {
        let clips = ["  Only clip  "]
        let merged = ClipMergeUtility.merge(clips, delimiter: .doubleNewline)
        #expect(merged == "Only clip")
    }

    @Test func mergeEmptyListReturnsEmptyString() {
        let merged = ClipMergeUtility.merge([], delimiter: .doubleNewline)
        #expect(merged.isEmpty)
    }
}
