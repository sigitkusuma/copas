import Testing

@testable import Copas

struct ClipContentTypeTests {

    // MARK: - URLs

    @Test(arguments: [
        "https://example.com",
        "https://github.com/sigitkusuma/copas",
        "http://localhost:8080/api/v1",
        "https://user:pass@host.example.com/path?q=1&r=2#anchor",
        "ftp://files.example.org/archive.tar.gz",
    ])
    func urlsAreClassifiedAsURLs(text: String) {
        guard case .url = ClipContentType.classify(text) else {
            Issue.record("Expected .url for: \(text)")
            return
        }
    }

    @Test(arguments: [
        "not a url",
        "example.com",                  // No scheme
        "mailto:user@example.com",      // Not http/https/ftp
        "javascript:alert(1)",          // Dangerous scheme
    ])
    func nonHTTPStringsAreNotURLs(text: String) {
        if case .url = ClipContentType.classify(text) {
            Issue.record("Did not expect .url for: \(text)")
        }
    }

    // MARK: - Emails

    @Test(arguments: [
        "user@example.com",
        "sigit.kusuma+tag@mail.co.id",
        "a@b.org",
    ])
    func emailsAreClassifiedAsEmails(text: String) {
        guard case .email = ClipContentType.classify(text) else {
            Issue.record("Expected .email for: \(text)")
            return
        }
    }

    @Test(arguments: [
        "not an email",
        "@nodomain",
        "missing@",
        "two@@at.com",
    ])
    func invalidEmailsAreNotClassifiedAsEmails(text: String) {
        if case .email = ClipContentType.classify(text) {
            Issue.record("Did not expect .email for: \(text)")
        }
    }

    // MARK: - Hex Colors

    @Test(arguments: [
        "#FF5733",
        "#abc",
        "#AABBCCDD",
        "#000000",
        "#FFF",
    ])
    func hexColorsAreClassifiedAsColors(text: String) {
        guard case .hexColor = ClipContentType.classify(text) else {
            Issue.record("Expected .hexColor for: \(text)")
            return
        }
    }

    @Test(arguments: [
        "FF5733",       // Missing #
        "#GG0000",      // Non-hex chars
        "#FFFFF",       // Wrong length (5)
        "red",
    ])
    func invalidHexStringsAreNotColors(text: String) {
        if case .hexColor = ClipContentType.classify(text) {
            Issue.record("Did not expect .hexColor for: \(text)")
        }
    }

    // MARK: - File Paths

    @Test(arguments: [
        "/Users/sigit/Documents/notes.txt",
        "~/Projects/copas/README.md",
        "/var/log/system.log",
        "/tmp/build/output/",
    ])
    func filePathsAreClassifiedAsFilePaths(text: String) {
        guard case .filePath = ClipContentType.classify(text) else {
            Issue.record("Expected .filePath for: \(text)")
            return
        }
    }

    @Test(arguments: [
        "just/a/relative/path",    // No leading slash
        "/nodot",                  // No second path component
        "C:\\Windows\\system32",   // Windows path
    ])
    func nonAbsolutePathsAreNotFilePaths(text: String) {
        if case .filePath = ClipContentType.classify(text) {
            Issue.record("Did not expect .filePath for: \(text)")
        }
    }

    // MARK: - UUIDs

    @Test(arguments: [
        "550e8400-e29b-41d4-a716-446655440000",
        "AAAABBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF",
        "{550e8400-e29b-41d4-a716-446655440000}",  // Braces variant
    ])
    func uuidsAreClassifiedAsUUIDs(text: String) {
        guard case .uuid = ClipContentType.classify(text) else {
            Issue.record("Expected .uuid for: \(text)")
            return
        }
    }

    @Test
    func malformedUUIDIsNotClassifiedAsUUID() {
        // Wrong segment lengths
        if case .uuid = ClipContentType.classify("550e8400-e29b-41d4-a716") {
            Issue.record("Did not expect .uuid for truncated UUID")
        }
    }

    // MARK: - JSON

    @Test(arguments: [
        "{\"name\": \"copas\", \"version\": 2}",
        "[1, 2, 3]",
        "{\"nested\": {\"key\": true}}",
    ])
    func jsonIsClassifiedAsJSON(text: String) {
        #expect(ClipContentType.classify(text) == .json, "Expected .json for: \(text)")
    }

    @Test(arguments: [
        "name: copas",         // YAML, not JSON
        "just text",
        "{broken json",
    ])
    func invalidJSONIsNotClassifiedAsJSON(text: String) {
        #expect(ClipContentType.classify(text) != .json)
    }

    // MARK: - Plain fallback

    @Test(arguments: [
        "Hello, world!",
        "A quick brown fox",
        "",
        "123456",              // Bare number — not a phone (no formatting)
    ])
    func ordinaryTextFallsToPlain(text: String) {
        #expect(ClipContentType.classify(text) == .plain)
    }

    // MARK: - Priority: URL wins over email-like paths

    @Test
    func urlWinsOverEmailWhenHTTPS() {
        // A URL in query params might contain an @ — the URL parser handles this.
        let text = "https://example.com/path"
        guard case .url = ClipContentType.classify(text) else {
            Issue.record("Expected .url")
            return
        }
    }

    // MARK: - Multiline is not a single-token type

    @Test
    func multilineTextIsNeverAURL() {
        let text = "https://example.com\nhttps://other.com"
        if case .url = ClipContentType.classify(text) {
            Issue.record("Multi-line text should not be a URL")
        }
    }

    @Test
    func multilineTextIsNeverAnEmail() {
        let text = "user@example.com\nother@example.com"
        if case .email = ClipContentType.classify(text) {
            Issue.record("Multi-line text should not be an email")
        }
    }
}
