import Foundation
import SwiftUI

/// Finds and marks the searched-for words inside a clip.
///
/// Pure string work, kept out of the views: what a card shows when a search
/// matches somewhere the card was not already displaying is a decision worth
/// testing, and it is impossible to test through a `body`.
enum SearchHighlight {

    /// Where each term appears, merged so overlapping matches highlight once.
    ///
    /// Case- and diacritic-insensitive, to agree with the FTS tokeniser: a search
    /// that finds a clip and then fails to point at the word in it looks broken.
    static func ranges(of terms: [String], in text: String) -> [Range<String.Index>] {
        guard !terms.isEmpty, !text.isEmpty else { return [] }

        var found: [Range<String.Index>] = []
        for term in terms where !term.isEmpty {
            var searchStart = text.startIndex
            while
                searchStart < text.endIndex,
                let range = text.range(
                    of: term,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchStart..<text.endIndex
                )
            {
                found.append(range)
                searchStart = range.upperBound
                // A pathological query against a long clip should not turn a
                // card into a quadratic search.
                if found.count >= 64 { break }
            }
        }

        return merged(found)
    }

    static func matches(_ terms: [String], in text: String?) -> Bool {
        guard let text else { return false }
        return !ranges(of: terms, in: text).isEmpty
    }

    /// A window of text around the first match.
    ///
    /// Used when a search finds a clip somewhere the card is not already showing
    /// — inside a long clip's body, or inside the text recognised from a
    /// screenshot. Without it a search returns a card with no visible reason to
    /// be there.
    static func excerpt(from text: String, matching terms: [String], limit: Int = 180) -> String? {
        guard let first = ranges(of: terms, in: text).first else { return nil }

        // Roughly a third of the window ahead of the match, so the matched word
        // lands where the eye is rather than hard against an edge.
        let matchOffset = text.distance(from: text.startIndex, to: first.lowerBound)
        let startOffset = max(0, matchOffset - limit / 3)
        let start = text.index(text.startIndex, offsetBy: startOffset)
        let end = text.index(start, offsetBy: limit, limitedBy: text.endIndex) ?? text.endIndex

        var excerpt = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if startOffset > 0 { excerpt = "…" + excerpt }
        if end < text.endIndex { excerpt += "…" }
        return excerpt
    }

    /// The text with its matches marked for display.
    static func attributed(_ text: String, terms: [String]) -> AttributedString {
        var attributed = AttributedString(text)
        guard !terms.isEmpty else { return attributed }

        for range in ranges(of: terms, in: text) {
            guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed)
            else { continue }
            attributed[lower..<upper].backgroundColor = Theme.accent.opacity(0.22)
            attributed[lower..<upper].foregroundColor = Theme.accent
        }
        return attributed
    }

    private static func merged(_ ranges: [Range<String.Index>]) -> [Range<String.Index>] {
        guard ranges.count > 1 else { return ranges }
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }

        var merged: [Range<String.Index>] = [sorted[0]]
        for range in sorted.dropFirst() {
            let last = merged[merged.count - 1]
            if range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
