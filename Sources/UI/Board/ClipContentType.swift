import Foundation

/// What a text clip appears to contain.
///
/// Classification is fast and one-shot: the first match wins. The intent is
/// that we detect the *primary* purpose of what was copied, not every type
/// present. A URL with a query-string that contains an email is a URL.
///
/// All detection runs against a prefix of the text (``sampleLimit``), so a
/// 4 MB log file never stalls the UI thread on its way to ``plain``.
enum ClipContentType: Hashable, Sendable {
    case url(URL)
    case email(String)
    case phone(String)
    /// The raw hex string, e.g. `"#FF5733"` or `"#abc"`.
    case hexColor(String)
    /// Valid JSON object or array.
    case json
    /// An absolute or home-relative filesystem path.
    case filePath(String)
    /// An 8-4-4-4-12 UUID string.
    case uuid(String)
    /// Nothing recognised — ordinary prose or code.
    case plain
}

extension ClipContentType {

    /// How much of the clip we look at. Enough to catch the overwhelming
    /// majority of cases; cheap regardless of how long the clip is.
    private static let sampleLimit = 2048

    /// Classifies `text`, returning the first match.
    ///
    /// The order below is the priority order. A UUID looks like a bareword
    /// but UUIDs are more useful to identify than generic words, so they are
    /// checked before we fall through to plain.
    static func classify(_ text: String) -> ClipContentType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sample = String(trimmed.prefix(sampleLimit))

        if let type = asURL(sample) { return type }
        if let type = asEmail(sample) { return type }
        if let type = asPhone(sample) { return type }
        if let type = asHexColor(sample) { return type }
        if let type = asFilePath(sample) { return type }
        if let type = asUUID(sample) { return type }
        if isJSON(sample) { return .json }

        return .plain
    }

    // MARK: - Individual detectors

    private static func asURL(_ sample: String) -> ClipContentType? {
        // Must be a single token (no internal whitespace).
        guard !sample.contains(" "), !sample.contains("\n") else { return nil }
        guard let url = URL(string: sample) else { return nil }
        let scheme = url.scheme?.lowercased() ?? ""
        guard ["http", "https", "ftp", "ftps"].contains(scheme) else { return nil }
        // Require at least a host — `http:` alone is a valid URL but useless.
        guard let host = url.host, !host.isEmpty else { return nil }
        return .url(url)
    }

    private static func asEmail(_ sample: String) -> ClipContentType? {
        guard !sample.contains("\n"), !sample.contains(" ") else { return nil }
        // RFC 5321 simplified: local@domain.tld
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        guard sample.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return .email(sample)
    }

    private static func asPhone(_ sample: String) -> ClipContentType? {
        // Accepts the common international formats:
        //   +1 (800) 555-0100
        //   +62-21-5551234
        //   0800 555 0100
        guard !sample.contains("\n") else { return nil }
        let stripped = sample.filter { $0.isNumber || "+(). -".contains($0) }
        let digits = stripped.filter(\.isNumber)
        guard (7...15).contains(digits.count) else { return nil }
        let pattern = #"^[+\(]?[\d\s\-\.\(\)]{7,20}$"#
        guard sample.range(of: pattern, options: .regularExpression) != nil else { return nil }
        // Reject things that are just numbers (zip codes, IDs, etc.)
        let hasNonDigit = sample.contains { "+(). -".contains($0) }
        guard hasNonDigit || sample.hasPrefix("+") else { return nil }
        return .phone(sample)
    }

    private static func asHexColor(_ sample: String) -> ClipContentType? {
        guard !sample.contains(" "), !sample.contains("\n") else { return nil }
        // #RGB, #RRGGBB, #RRGGBBAA
        let pattern = #"^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"#
        guard sample.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return .hexColor(sample)
    }

    private static func asFilePath(_ sample: String) -> ClipContentType? {
        guard !sample.contains("\n") else { return nil }
        // Must start with / or ~/
        guard sample.hasPrefix("/") || sample.hasPrefix("~/") else { return nil }
        // Paths with spaces are common; paths with quote chars are suspicious.
        guard !sample.contains("\""), !sample.contains("'") else { return nil }
        // Must have at least one path separator after the root.
        guard sample.dropFirst().contains("/") else { return nil }
        return .filePath(sample)
    }

    private static func asUUID(_ sample: String) -> ClipContentType? {
        guard !sample.contains(" "), !sample.contains("\n") else { return nil }
        // 8-4-4-4-12 hex digits, case-insensitive, with optional braces.
        let pattern = #"^\{?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}?$"#
        guard sample.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return .uuid(sample)
    }

    private static func isJSON(_ sample: String) -> Bool {
        guard sample.hasPrefix("{") || sample.hasPrefix("[") else { return false }
        guard let data = sample.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}
