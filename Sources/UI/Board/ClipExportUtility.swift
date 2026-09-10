import AppKit
import UniformTypeIdentifiers

/// Utilities for exporting clips to files on disk via NSSavePanel.
public enum ClipExportUtility {

    /// Produces a filesystem-safe filename from a clip snippet.
    public static func sanitizeFilename(_ raw: String, fallback: String = "clip") -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = raw
            .components(separatedBy: allowed.inverted)
            .joined(separator: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
        let truncated = String(cleaned.prefix(32))
        return truncated.isEmpty ? fallback : truncated
    }

    /// Infers an appropriate filename and extension based on content classification.
    public static func suggestedFilename(for text: String) -> String {
        let type = ClipContentType.classify(text)
        let firstLine = text.components(separatedBy: .newlines).first ?? "clip"
        let base = sanitizeFilename(firstLine)

        switch type {
        case .json:
            return base.hasSuffix(".json") ? base : "\(base).json"
        case .url:
            return base.hasSuffix(".md") ? base : "\(base).md"
        default:
            return base.hasSuffix(".txt") ? base : "\(base).txt"
        }
    }

    /// Prompts the user with an NSSavePanel and writes the text clip to the chosen path.
    @MainActor
    public static func exportText(_ text: String, suggestedName: String? = nil, window: NSWindow? = nil) {
        let filename = suggestedName ?? suggestedFilename(for: text)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = filename

        let ext = (filename as NSString).pathExtension.lowercased()
        if ext == "json" {
            panel.allowedContentTypes = [.json]
        } else if ext == "md" {
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        } else {
            panel.allowedContentTypes = [.plainText]
        }

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url {
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    /// Prompts the user with an NSSavePanel and writes image data to disk as PNG.
    @MainActor
    public static func exportImage(data: Data, suggestedName: String = "clip.png", window: NSWindow? = nil) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.png]

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url {
                try? data.write(to: url, options: .atomic)
            }
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    /// Merges an array of clip strings and prompts to save the resulting block.
    @MainActor
    public static func exportMerged(texts: [String], delimiter: MergeDelimiter = .doubleNewline, window: NSWindow? = nil) {
        let merged = ClipMergeUtility.merge(texts, delimiter: delimiter)
        guard !merged.isEmpty else { return }
        exportText(merged, suggestedName: "merged-clips.txt", window: window)
    }
}
