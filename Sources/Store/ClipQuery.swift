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
    var bundleIDs: Set<String>

    init(match: String? = nil, kinds: Set<ClipKind> = [], bundleIDs: Set<String> = []) {
        self.match = match
        self.kinds = kinds
        self.bundleIDs = bundleIDs
    }

    static let all = ClipQuery()

    /// The everyday case: free text typed into the search field.
    static func text(_ input: String) -> ClipQuery {
        ClipQuery(match: matchExpression(for: input))
    }

    var isUnfiltered: Bool {
        match == nil && kinds.isEmpty && bundleIDs.isEmpty
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
        let tokens = input
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { token in token.contains(where: { $0.isLetter || $0.isNumber }) }

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
