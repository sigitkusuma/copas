import Testing

@testable import Copas

struct SearchQueryTests {

    @Test func plainTextBecomesTerms() {
        let query = SearchQuery("invoice april")
        #expect(query.terms == ["invoice", "april"])
        #expect(query.app == nil)
        #expect(query.kind == nil)
    }

    @Test func termsAreLowercasedForCaseInsensitiveMatching() {
        #expect(SearchQuery("InVoice").terms == ["invoice"])
    }

    @Test func aFilterTokenIsNotAlsoSearchedAsText() {
        let query = SearchQuery("app:xcode")
        #expect(query.app == "xcode")
        #expect(query.terms.isEmpty)
        #expect(query.compiled().match == nil)
    }

    @Test(arguments: [("image", ClipKind.image), ("img", .image), ("picture", .image),
                      ("text", .text), ("txt", .text), ("string", .text)])
    func typeFiltersAndTheirAliases(value: String, expected: ClipKind) {
        #expect(SearchQuery("type:\(value)").kind == expected)
    }

    @Test func hasTextFindsClipsCarryingRecognisedText() {
        #expect(SearchQuery("has:text").requiresRecognizedText)
        #expect(SearchQuery("has:ocr").requiresRecognizedText)
    }

    @Test func filtersCombineWithFreeText() {
        let query = SearchQuery("app:chrome type:image invoice")
        #expect(query.app == "chrome")
        #expect(query.kind == .image)
        #expect(query.terms == ["invoice"])
    }

    /// A URL or a `key: value` line must stay findable rather than being
    /// swallowed by the parser and filtering everything away. A filter syntax
    /// that eats a legitimate search reads as the search being broken.
    @Test(arguments: ["https://example.com", "type:banana", "has:legs", "note:to self"])
    func unknownColonTokensAreTreatedAsText(input: String) {
        let query = SearchQuery(input)
        #expect(!query.terms.isEmpty, "\(input) should still be searched for")
        #expect(query.kind == nil)
        #expect(!query.requiresRecognizedText)
    }

    /// Typing past the colon must not blank the board for a keystroke.
    @Test func aBareFilterIsIgnoredRatherThanMatchingNothing() {
        #expect(SearchQuery("app:").app == nil)
        #expect(SearchQuery("app:").isEmpty)
    }

    @Test func extraWhitespaceDoesNotProduceEmptyTerms() {
        #expect(SearchQuery("  invoice   april  ").terms == ["invoice", "april"])
    }

    @Test func anEmptySearchIsUnfiltered() {
        #expect(SearchQuery("").isEmpty)
        #expect(SearchQuery("   ").compiled().isUnfiltered)
    }

    // MARK: - Compilation

    @Test func onlyFreeTextReachesTheFullTextIndex() {
        let compiled = SearchQuery("app:xcode type:text invoice april").compiled()

        #expect(compiled.match == "\"invoice\" AND \"april\"*")
        #expect(compiled.kinds == [.text])
        #expect(compiled.appFragment == "xcode")
    }

    @Test func aFilterOnlySearchStillFilters() {
        let compiled = SearchQuery("type:image has:text").compiled()

        #expect(compiled.match == nil)
        #expect(compiled.kinds == [.image])
        #expect(compiled.requiresRecognizedText)
        #expect(!compiled.isUnfiltered)
    }
}
