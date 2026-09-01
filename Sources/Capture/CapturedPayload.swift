import Foundation

/// Text as it came off the pasteboard, in every format the source app offered.
///
/// A rich editor puts plain text, RTF and HTML on the pasteboard at once. Keeping
/// only `plain` is what makes a clipboard manager quietly destructive: paste
/// something back and the formatting is gone, with nothing to say it was ever
/// there.
struct RichText: Sendable, Equatable {
    var plain: String
    var rtf: Data?
    var html: Data?

    init(plain: String, rtf: Data? = nil, html: Data? = nil) {
        self.plain = plain
        self.rtf = rtf
        self.html = html
    }

    var isEmpty: Bool { plain.isEmpty }
    var hasAlternates: Bool { rtf != nil || html != nil }
}

/// What a pasteboard change turned out to contain.
///
/// A value, with no reference to a database, a repository or a pasteboard. That
/// is the point: ``PasteboardMonitor`` produces these and knows nothing about
/// storage, and ``ClipIngestor`` consumes them and knows nothing about AppKit,
/// so each can be tested without the other.
struct CapturedPayload: Sendable, Equatable {

    enum Content: Sendable, Equatable {
        case text(RichText)
        /// Canonical image bytes, already normalised to PNG where possible.
        case image(Data)
    }

    var content: Content
    var source: SourceApp
    var capturedAt: Date

    /// The pasteboard change count this came from. Carried through so a caller
    /// can tell the monitor to disregard its own write — see
    /// ``PasteboardMonitor/suppress(upTo:)``.
    var changeCount: Int

    init(content: Content, source: SourceApp = SourceApp(), capturedAt: Date = Date(), changeCount: Int = 0) {
        self.content = content
        self.source = source
        self.capturedAt = capturedAt
        self.changeCount = changeCount
    }

    var isEmpty: Bool {
        switch content {
        case .text(let text): return text.isEmpty
        case .image(let data): return data.isEmpty
        }
    }
}
