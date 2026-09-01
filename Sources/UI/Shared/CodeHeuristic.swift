import Foundation

/// Guesses whether a snippet is code, so a card can set it in a monospaced face.
///
/// A guess, deliberately, and a cheap one — it reads a few hundred characters and
/// counts. Getting it wrong costs a snippet set in the wrong typeface; anything
/// heavier than this would cost a frame on every card that scrolls into view,
/// which is a far worse trade.
enum CodeHeuristic {

    /// Structural punctuation. Prose has commas, dashes and full stops; none of
    /// those are here. `#` and `@` are deliberately absent too — they would flag
    /// every hashtag and every mention as code.
    private static let structural: Set<Character> = [
        "{", "}", "[", "]", "(", ")", "<", ">", ";", "=", "/", "\\", "|", "*", "&", "^", "~", "`", "+",
    ]

    static func looksLikeCode(_ text: String) -> Bool {
        let sample = text.prefix(400)

        var structuralCount = 0
        var characterCount = 0
        for character in sample where !character.isWhitespace {
            characterCount += 1
            if structural.contains(character) { structuralCount += 1 }
        }

        // Too short to tell. A card showing four words in a monospaced face
        // because one of them was "C++" looks like a bug.
        guard characterCount >= 12 else { return false }

        if Double(structuralCount) / Double(characterCount) >= 0.12 { return true }

        let lines = sample.split(separator: "\n", omittingEmptySubsequences: false)

        // A line that ends in a brace or a semicolon is the clearest single
        // signal there is, and catches SQL and shell that are otherwise sparse.
        if lines.contains(where: {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return trimmed.hasSuffix("{") || trimmed.hasSuffix(";") || trimmed.hasSuffix("},")
        }) { return true }

        // Indentation across several lines. Prose wraps; code is arranged.
        if lines.count >= 3 {
            let indented = lines.count { $0.hasPrefix("  ") || $0.hasPrefix("\t") }
            if indented >= 2 { return true }
        }

        return false
    }
}
