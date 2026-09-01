import Foundation

/// Everything the repository needs to fetch a page.
///
/// Deliberately a plain value with no parsing in it. The search grammar compiles
/// user input *into* this, which keeps the grammar testable without a database
/// and keeps the repository free of any opinion about syntax.
struct ClipQuery: Equatable, Sendable {

    /// A ready-to-use FTS5 MATCH expression, or `nil` to match every clip.
    /// Never raw user input — see ``matchExpression(for:)``.
    var match: String?

    /// Empty means "all kinds".
    var kinds: Set<ClipKind>

    /// Restricts to clips copied from these bundle identifiers. Empty means "any".
    ///
    /// Exact, for filters the app sets itself. What a person *types* goes in
    /// ``appFragment`` instead — nobody types a bundle identifier.
    var bundleIDs: Set<String>

    /// A case-insensitive fragment matched against the app's display name or its
    /// bundle identifier, whichever the user happened to have in mind.
    var appFragment: String?

    /// Only clips carrying recognised text.
    var requiresRecognizedText: Bool

    init(
        match: String? = nil,
        kinds: Set<ClipKind> = [],
        bundleIDs: Set<String> = [],
        appFragment: String? = nil,
        requiresRecognizedText: Bool = false
    ) {
        self.match = match
        self.kinds = kinds
        self.bundleIDs = bundleIDs
        self.appFragment = appFragment
        self.requiresRecognizedText = requiresRecognizedText
    }

    static let all = ClipQuery()

    /// The everyday case: free text typed into the search field.
    static func text(_ input: String) -> ClipQuery {
        ClipQuery(match: matchExpression(for: input))
    }

    var isUnfiltered: Bool {
        match == nil && kinds.isEmpty && bundleIDs.isEmpty
            && appFragment == nil && !requiresRecognizedText
    }

    /// Turns typed text into a safe FTS5 expression.
    ///
    /// Every token is wrapped in double quotes — with embedded quotes doubled —
    /// so operators the user did not intend (`OR`, `NOT`, `*`, `:`, parentheses)
    /// are searched for rather than executed. An unescaped field would not just
    /// return wrong results; a stray quote is a syntax error, so search would
    /// break outright the first time somebody looked for `"` or `AND`.
    ///
    /// Only the final token gets a prefix `*`. Prefixing all of them would make a
    /// finished search for `cat dog` also match `category dogma`, which reads as
    /// the search being wrong; prefixing the last one is what makes typing feel
    /// live.
    static func matchExpression(for input: String) -> String? {
        matchExpression(forTerms: input.split(whereSeparator: \.isWhitespace).map(String.init))
    }

    /// The same rules, applied to terms a grammar has already separated from its
    /// filter tokens — so `app:xcode` is never also searched for as text.
    static func matchExpression(forTerms terms: [String]) -> String? {
        let tokens = terms.filter { token in token.contains(where: { $0.isLetter || $0.isNumber }) }

        guard !tokens.isEmpty else { return nil }

        return tokens.enumerated().map { index, token in
            let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
            let isLast = index == tokens.count - 1
            return "\"\(escaped)\"" + (isLast ? "*" : "")
        }.joined(separator: " AND ")
    }
}

/// Where a page of results stops, so the next page can pick up exactly there.
///
/// Carries the id as well as the timestamp because two clips can share a
/// millisecond — offset paging would then either repeat or skip a row whenever a
/// new clip arrived mid-scroll.
struct ClipCursor: Equatable, Sendable {
    var createdAt: Double
    var id: String

    init(createdAt: Double, id: String) {
        self.createdAt = createdAt
        self.id = id
    }

    init(_ record: ClipRecord) {
        self.init(createdAt: record.createdAt, id: record.id)
    }
}
