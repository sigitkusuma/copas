import Foundation

/// Available delimiters for combining multiple clips into a single text block.
public enum MergeDelimiter: String, CaseIterable, Identifiable, Sendable {
    case doubleNewline = "Paragraphs"
    case singleNewline = "Newlines"
    case comma = "Commas"
    case tab = "Tabs"
    case space = "Spaces"

    public var id: String { rawValue }

    public var separator: String {
        switch self {
        case .doubleNewline: return "\n\n"
        case .singleNewline: return "\n"
        case .comma: return ", "
        case .tab: return "\t"
        case .space: return " "
        }
    }

    public var icon: String {
        switch self {
        case .doubleNewline: return "paragraphsign"
        case .singleNewline: return "return"
        case .comma: return "character"
        case .tab: return "arrow.right.to.line"
        case .space: return "space"
        }
    }
}

/// Pure helper for combining multiple clips into a unified text block.
public enum ClipMergeUtility {

    /// Merges an ordered sequence of clip strings using the given delimiter.
    /// Empty clips are discarded to avoid stray separators.
    public static func merge(_ texts: [String], delimiter: MergeDelimiter = .doubleNewline) -> String {
        texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: delimiter.separator)
    }
}
