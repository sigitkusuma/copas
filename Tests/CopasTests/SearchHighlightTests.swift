import Testing

@testable import Copas

struct SearchHighlightTests {

    @Test func matchesAreFoundRegardlessOfCase() {
        let text = "Invoice 4471"
        #expect(SearchHighlight.ranges(of: ["invoice"], in: text).count == 1)
        #expect(SearchHighlight.matches(["INVOICE"], in: text))
    }

    /// Agrees with the FTS tokeniser, which folds diacritics. A search that finds
    /// a clip and then cannot point at the word in it looks broken.
    @Test func matchesIgnoreDiacritics() {
        #expect(SearchHighlight.matches(["cafe"], in: "Café Batavia"))
    }

    @Test func everyOccurrenceIsFound() {
        #expect(SearchHighlight.ranges(of: ["the"], in: "the cat and the hat").count == 2)
    }

    /// Two terms covering the same characters must highlight once, not twice —
    /// overlapping attribute runs render as a darker, ragged block.
    @Test func overlappingMatchesAreMerged() {
        let ranges = SearchHighlight.ranges(of: ["inv", "invoice"], in: "invoice")
        #expect(ranges.count == 1)
    }

    @Test func nothingToFindMeansNoRanges() {
        #expect(SearchHighlight.ranges(of: ["missing"], in: "invoice").isEmpty)
        #expect(SearchHighlight.ranges(of: [], in: "invoice").isEmpty)
        #expect(SearchHighlight.ranges(of: ["a"], in: "").isEmpty)
    }

    // MARK: - Excerpts

    @Test func anExcerptIsCentredNearTheMatch() {
        let text = String(repeating: "padding ", count: 60) + "NEEDLE" + String(repeating: " tail", count: 60)
        let excerpt = try! #require(SearchHighlight.excerpt(from: text, matching: ["needle"], limit: 90))

        #expect(excerpt.contains("NEEDLE"))
        #expect(excerpt.hasPrefix("…"))
        #expect(excerpt.hasSuffix("…"))
        #expect(excerpt.count <= 92)
    }

    @Test func anExcerptFromTheStartHasNoLeadingEllipsis() {
        let excerpt = try! #require(
            SearchHighlight.excerpt(from: "NEEDLE in a short haystack", matching: ["needle"], limit: 90)
        )
        #expect(excerpt == "NEEDLE in a short haystack")
    }

    @Test func noMatchMeansNoExcerpt() {
        #expect(SearchHighlight.excerpt(from: "haystack", matching: ["needle"]) == nil)
        #expect(SearchHighlight.excerpt(from: "haystack", matching: []) == nil)
    }
}
