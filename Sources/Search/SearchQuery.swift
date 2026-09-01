import Foundation

/// A search string split into filter tokens and free-text terms.
///
/// The syntax is the one already half-learned from every other search field:
///
///     app:xcode              copied from Xcode
///     type:image invoice     images whose text mentions "invoice"
///     has:text receipt       pictures with recognised text, mentioning "receipt"
///
/// Unrecognised `word:word` input is treated as ordinary search text rather than
/// silently filtering everything away. Somebody looking for a URL or a
/// `key: value` line they copied must still find it — a filter syntax that eats
/// a legitimate search and returns nothing reads as the search being broken.
struct SearchQuery: Equatable, Sendable {

    /// Lowercased free-text terms; a clip must match all of them.
    private(set) var terms: [String] = []

    /// Matched against the app's name *or* its bundle identifier, as a
    /// case-insensitive fragment — "xcode" should find both `Xcode` and
    /// `com.apple.dt.Xcode` without the user knowing which is which.
    private(set) var app: String?

    private(set) var kind: ClipKind?

    /// `has:text` — only clips carrying recognised text.
    private(set) var requiresRecognizedText = false

    init(_ raw: String) {
        for token in raw.split(whereSeparator: \.isWhitespace).map(String.init) {
            let lowercased = token.lowercased()

            if let value = Self.value(after: "app:", in: lowercased) {
                // A bare `app:` filters to nothing, which as you type past the
                // colon would blank the board for a keystroke.
                if value.isEmpty { continue }
                app = value

            } else if let value = Self.value(after: "type:", in: lowercased) {
                switch value {
                case "image", "img", "picture": kind = .image
                case "text", "txt", "string": kind = .text
                default: terms.append(lowercased)
                }

            } else if let value = Self.value(after: "has:", in: lowercased) {
                switch value {
                case "text", "ocr": requiresRecognizedText = true
                default: terms.append(lowercased)
                }

            } else {
                terms.append(lowercased)
            }
        }
    }

    private static func value(after prefix: String, in token: String) -> String? {
        guard token.hasPrefix(prefix) else { return nil }
        return String(token.dropFirst(prefix.count))
    }

    var isEmpty: Bool {
        terms.isEmpty && app == nil && kind == nil && !requiresRecognizedText
    }

    /// Turns the parsed search into something the repository can run.
    ///
    /// Only ``terms`` reach the full-text index — the filter tokens are consumed
    /// here, so typing `app:xcode` never also searches for the literal text
    /// "app:xcode".
    func compiled() -> ClipQuery {
        ClipQuery(
            match: ClipQuery.matchExpression(forTerms: terms),
            kinds: kind.map { [$0] } ?? [],
            appFragment: app,
            requiresRecognizedText: requiresRecognizedText
        )
    }
}
