import Foundation
import Testing

@testable import Copas

struct TextTransformTests {

    // MARK: - Case transforms

    @Test func uppercaseTransform() {
        #expect(TextTransform.uppercase.apply("hello world") == "HELLO WORLD")
    }

    @Test func lowercaseTransform() {
        #expect(TextTransform.lowercase.apply("HELLO WORLD") == "hello world")
    }

    @Test func titleCaseTransform() {
        #expect(TextTransform.titleCase.apply("hello world") == "Hello World")
    }

    // MARK: - Whitespace

    @Test func trimWhitespaceStripsLeadingAndTrailing() {
        #expect(TextTransform.trimWhitespace.apply("  hello  ") == "hello")
    }

    @Test func trimWhitespaceCollapsesMultipleBlankLines() {
        let input = "line1\n\n\n\nline2"
        let result = TextTransform.trimWhitespace.apply(input)
        // Multiple blank lines should become at most one.
        #expect(!result.contains("\n\n\n"))
        #expect(result.contains("line1"))
        #expect(result.contains("line2"))
    }

    @Test func trimWhitespaceTrimsTrailingSpacesPerLine() {
        let input = "hello   \nworld   "
        let result = TextTransform.trimWhitespace.apply(input)
        for line in result.components(separatedBy: "\n") {
            #expect(!line.hasSuffix(" "), "Line should not have trailing space: '\(line)'")
        }
    }

    // MARK: - Line operations

    @Test func sortLinesAlphabetically() {
        let input = "banana\napple\ncherry"
        #expect(TextTransform.sortLines.apply(input) == "apple\nbanana\ncherry")
    }

    @Test func removeDuplicateLinesKeepsOrder() {
        let input = "a\nb\na\nc\nb"
        #expect(TextTransform.removeDuplicateLines.apply(input) == "a\nb\nc")
    }

    @Test func numberLinesPrefixesEachLine() {
        let input = "alpha\nbeta\ngamma"
        #expect(TextTransform.numberLines.apply(input) == "1. alpha\n2. beta\n3. gamma")
    }

    // MARK: - URL encode/decode

    @Test func urlEncodeEncodesSpacesAndSpecials() {
        let result = TextTransform.urlEncode.apply("hello world & co")
        #expect(result.contains("%20") || result.contains("+"))
        #expect(!result.contains(" "))
    }

    @Test func urlDecodeRoundTrips() {
        let original = "hello world"
        let encoded = TextTransform.urlEncode.apply(original)
        let decoded = TextTransform.urlDecode.apply(encoded)
        #expect(decoded == original)
    }

    // MARK: - Base64

    @Test func base64EncodeAndDecode() {
        let original = "Copas clipboard manager"
        let encoded = TextTransform.base64Encode.apply(original)
        let decoded = TextTransform.base64Decode.apply(encoded)
        #expect(decoded == original)
    }

    @Test func base64DecodeOnNonBase64ReturnsInput() {
        let garbage = "this is not base64 !!!@@@"
        #expect(TextTransform.base64Decode.apply(garbage) == garbage)
    }

    // MARK: - JSON

    @Test func jsonPrettyPrintFormatsJSON() {
        let input = "{\"b\":2,\"a\":1}"
        let result = TextTransform.jsonPrettyPrint.apply(input)
        // Pretty-printed JSON should have newlines and indentation.
        #expect(result.contains("\n"))
        #expect(result.contains("  "))
    }

    @Test func jsonCompactMinifiesJSON() {
        let input = """
            {
              "name": "copas",
              "version": 2
            }
            """
        let result = TextTransform.jsonCompact.apply(input)
        #expect(!result.contains("\n"))
    }

    @Test func jsonTransformOnInvalidJSONReturnsInput() {
        let notJSON = "not json at all"
        #expect(TextTransform.jsonPrettyPrint.apply(notJSON) == notJSON)
        #expect(TextTransform.jsonCompact.apply(notJSON) == notJSON)
    }

    @Test func jsonPrettyThenCompactRoundTrips() {
        let input = "{\"key\":\"value\",\"count\":42}"
        let pretty = TextTransform.jsonPrettyPrint.apply(input)
        let compact = TextTransform.jsonCompact.apply(pretty)
        // Re-parsed, both should equal the same object. Compare via JSON round-trip.
        let d1 = compact.data(using: .utf8)!
        let d2 = input.data(using: .utf8)!
        let o1 = try? JSONSerialization.jsonObject(with: d1) as? [String: Any]
        let o2 = try? JSONSerialization.jsonObject(with: d2) as? [String: Any]
        #expect(o1?["key"] as? String == o2?["key"] as? String)
        #expect(o1?["count"] as? Int == o2?["count"] as? Int)
    }

    // MARK: - Quote wrapping

    @Test func wrapInQuotes() {
        #expect(TextTransform.wrapInQuotes.apply("hello") == "\"hello\"")
    }

    @Test func wrapInQuotesPreservesInternalQuotes() {
        // We wrap, we do not escape — the intent is to wrap a blob, not to
        // produce a language literal.
        #expect(TextTransform.wrapInQuotes.apply("say \"hi\"") == "\"say \"hi\"\"")
    }

    // MARK: - HTML escaping

    @Test func escapeHTMLConvertsSpecialChars() {
        let input = "<div class=\"card\"> & 'hello'</div>"
        let result = TextTransform.escapeHTML.apply(input)
        #expect(result.contains("&lt;"))
        #expect(result.contains("&gt;"))
        #expect(result.contains("&quot;"))
        #expect(result.contains("&amp;"))
        #expect(result.contains("&#39;"))
        #expect(!result.contains("<"))
        #expect(!result.contains(">"))
    }

    // MARK: - Identity on already-transformed input

    @Test func uppercaseIsIdempotent() {
        let input = "HELLO"
        #expect(TextTransform.uppercase.apply(input) == input)
    }

    @Test func sortLinesOnSingleLineReturnsItself() {
        let input = "only one line"
        #expect(TextTransform.sortLines.apply(input) == input)
    }

    // MARK: - Empty string is always safe

    @Test(arguments: TextTransform.allCases)
    func everyTransformHandlesEmptyString(transform: TextTransform) {
        // Should not crash, should return a String (possibly empty).
        let result = transform.apply("")
        _ = result  // Just assert it did not throw / return nil
    }

    // MARK: - available(for:)

    @Test func jsonTransformsAreAptForJSON() {
        let json = "{\"key\": \"value\"}"
        let available = TextTransform.available(for: json)
        let labels = available.prefix(5).map(\.label)
        #expect(labels.contains("JSON Pretty Print") || labels.contains("JSON Compact"))
    }

    @Test func sortLinesIsAptForMultilineText() {
        let text = "banana\napple\ncherry"
        let available = TextTransform.available(for: text)
        let leading = available.prefix(5).map(\.label)
        #expect(leading.contains("Sort Lines"))
    }

    @Test func availableAlwaysReturnsAllTransforms() {
        let count = TextTransform.allCases.count
        #expect(TextTransform.available(for: "hello").count == count)
        #expect(TextTransform.available(for: "").count == count)
    }
}
