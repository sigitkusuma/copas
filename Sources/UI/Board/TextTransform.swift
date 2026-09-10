import AppKit
import Foundation

/// A reversible or irreversible transformation applied to clip text.
///
/// Transforms operate on the *result* copied to the pasteboard — the original
/// clip in the database is never mutated. A transform that fails (e.g., Base64
/// decode on non-Base64 input) silently returns the input unchanged, which is
/// always a safe fallback.
enum TextTransform: CaseIterable, Identifiable, Sendable {

    case uppercase
    case lowercase
    case titleCase
    case trimWhitespace
    case sortLines
    case removeDuplicateLines
    case urlEncode
    case urlDecode
    case base64Encode
    case base64Decode
    case jsonPrettyPrint
    case jsonCompact
    case wrapInQuotes
    case escapeHTML
    case numberLines

    var id: String { label }

    var label: String {
        switch self {
        case .uppercase:            return "UPPERCASE"
        case .lowercase:            return "lowercase"
        case .titleCase:            return "Title Case"
        case .trimWhitespace:       return "Trim Whitespace"
        case .sortLines:            return "Sort Lines"
        case .removeDuplicateLines: return "Remove Duplicate Lines"
        case .urlEncode:            return "URL Encode"
        case .urlDecode:            return "URL Decode"
        case .base64Encode:         return "Base64 Encode"
        case .base64Decode:         return "Base64 Decode"
        case .jsonPrettyPrint:      return "JSON Pretty Print"
        case .jsonCompact:          return "JSON Compact"
        case .wrapInQuotes:         return "Wrap in Quotes"
        case .escapeHTML:           return "Escape HTML"
        case .numberLines:          return "Number Lines"
        }
    }

    var systemImage: String {
        switch self {
        case .uppercase:            return "textformat.size.larger"
        case .lowercase:            return "textformat.size.smaller"
        case .titleCase:            return "textformat"
        case .trimWhitespace:       return "scissors"
        case .sortLines:            return "arrow.up.arrow.down"
        case .removeDuplicateLines: return "line.3.horizontal.decrease"
        case .urlEncode:            return "link"
        case .urlDecode:            return "link.badge.plus"
        case .base64Encode:         return "lock"
        case .base64Decode:         return "lock.open"
        case .jsonPrettyPrint:      return "curlybraces"
        case .jsonCompact:          return "curlybraces.square"
        case .wrapInQuotes:         return "text.quote"
        case .escapeHTML:           return "chevron.left.forwardslash.chevron.right"
        case .numberLines:          return "list.number"
        }
    }

    // MARK: - Apply

    /// Applies the transform to `input` and returns the result.
    ///
    /// Never throws. If a transform cannot meaningfully process the input
    /// (e.g., `base64Decode` on arbitrary text), it returns the input
    /// unchanged — the caller sees a copy with the original content, which
    /// is always a safe outcome.
    func apply(_ input: String) -> String {
        switch self {
        case .uppercase:
            return input.uppercased()

        case .lowercase:
            return input.lowercased()

        case .titleCase:
            return titleCased(input)

        case .trimWhitespace:
            return trimmed(input)

        case .sortLines:
            return input.components(separatedBy: "\n").sorted().joined(separator: "\n")

        case .removeDuplicateLines:
            var seen = Set<String>()
            return input
                .components(separatedBy: "\n")
                .filter { seen.insert($0).inserted }
                .joined(separator: "\n")

        case .urlEncode:
            return input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input

        case .urlDecode:
            return input.removingPercentEncoding ?? input

        case .base64Encode:
            return Data(input.utf8).base64EncodedString()

        case .base64Decode:
            guard let data = Data(base64Encoded: input, options: .ignoreUnknownCharacters),
                  let decoded = String(data: data, encoding: .utf8)
            else { return input }
            return decoded

        case .jsonPrettyPrint:
            guard let data = input.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let pretty = try? JSONSerialization.data(
                      withJSONObject: object,
                      options: [.prettyPrinted, .sortedKeys]
                  ),
                  let result = String(data: pretty, encoding: .utf8)
            else { return input }
            return result

        case .jsonCompact:
            guard let data = input.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let compact = try? JSONSerialization.data(withJSONObject: object),
                  let result = String(data: compact, encoding: .utf8)
            else { return input }
            return result

        case .wrapInQuotes:
            return "\"\(input)\""

        case .escapeHTML:
            return input
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")

        case .numberLines:
            return input
                .components(separatedBy: "\n")
                .enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
        }
    }

    // MARK: - Availability

    /// Returns the transforms that make sense for `text`.
    ///
    /// Every transform is always *available* (a user who wants to base64
    /// encode plain prose can), but a subset are *highlighted* as
    /// particularly apt. Calling this returns the full list in a sensible
    /// order: apt transforms first, then the rest.
    static func available(for text: String) -> [TextTransform] {
        // Put type-specific transforms first when they actually apply.
        var leading: [TextTransform] = []
        var trailing: [TextTransform] = []

        for transform in TextTransform.allCases {
            if transform.isApt(for: text) {
                leading.append(transform)
            } else {
                trailing.append(transform)
            }
        }

        return leading + trailing
    }

    /// Whether this transform is particularly apt for `text`.
    func isApt(for text: String) -> Bool {
        switch self {
        case .jsonPrettyPrint, .jsonCompact:
            guard let data = text.data(using: .utf8) else { return false }
            return (try? JSONSerialization.jsonObject(with: data)) != nil

        case .urlDecode:
            return text.contains("%") && text.removingPercentEncoding != text

        case .base64Decode:
            // Quick heuristic: looks like Base64 if it is a single token of
            // the right character set. Checking the byte length is exact.
            let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let isBase64Charset = stripped.allSatisfy {
                $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "="
            }
            return isBase64Charset && stripped.count % 4 == 0 && stripped.count >= 4

        case .sortLines, .removeDuplicateLines, .numberLines:
            return text.contains("\n")

        default:
            return false
        }
    }

    // MARK: - Private helpers

    private func titleCased(_ input: String) -> String {
        // Use the locale-aware method so ligatures and multi-script text behave.
        input.capitalized(with: Locale.current)
    }

    private func trimmed(_ input: String) -> String {
        let lines = input.components(separatedBy: "\n")
        // Per-line trailing trim + a single blank-line normalisation pass.
        var result: [String] = []
        var blankRun = 0

        for line in lines {
            let trimmedLine = line.replacingOccurrences(
                of: "\\s+$", with: "", options: .regularExpression
            )
            if trimmedLine.isEmpty {
                blankRun += 1
                if blankRun <= 1 { result.append("") }
            } else {
                blankRun = 0
                result.append(trimmedLine)
            }
        }

        // Remove a trailing blank the normaliser may have left.
        if result.last == "" { result.removeLast() }

        return result.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
