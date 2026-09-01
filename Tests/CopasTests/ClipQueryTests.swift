import Testing

@testable import Copas

struct ClipQueryTests {

    @Test func emptyInputMatchesEverything() {
        #expect(ClipQuery.matchExpression(for: "") == nil)
        #expect(ClipQuery.matchExpression(for: "   ") == nil)
        #expect(ClipQuery.text("").isUnfiltered)
    }

    @Test func onlyTheLastTokenIsAPrefix() {
        #expect(ClipQuery.matchExpression(for: "cat dog") == "\"cat\" AND \"dog\"*")
    }

    @Test func singleTokenIsAPrefix() {
        #expect(ClipQuery.matchExpression(for: "cat") == "\"cat\"*")
    }

    /// Operators typed into the search field are content, not syntax.
    @Test func operatorsAreQuotedRatherThanExecuted() {
        #expect(ClipQuery.matchExpression(for: "OR") == "\"OR\"*")
        #expect(ClipQuery.matchExpression(for: "a NOT b") == "\"a\" AND \"NOT\" AND \"b\"*")
    }

    @Test func embeddedQuotesAreDoubled() {
        #expect(ClipQuery.matchExpression(for: "say\"it") == "\"say\"\"it\"*")
    }

    /// A lone `-` or `"` tokenises to nothing, and feeding an empty phrase to
    /// FTS5 is how a search field starts throwing instead of finding.
    @Test func tokensWithoutLettersOrDigitsAreDropped() {
        #expect(ClipQuery.matchExpression(for: "- \" ()") == nil)
        #expect(ClipQuery.matchExpression(for: "-- swift") == "\"swift\"*")
    }
}
