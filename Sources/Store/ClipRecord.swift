import Foundation
import GRDB

/// What a clip holds. Stored as an integer so the set can grow without a migration.
enum ClipKind: Int, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    case text = 0
    case image = 1
}

/// The app a clip was copied from.
struct SourceApp: Sendable, Equatable, Hashable {
    var bundleID: String?
    var name: String?

    init(bundleID: String? = nil, name: String? = nil) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// One row of `clip`.
///
/// Three things here are deliberate departures from the model this app replaces:
///
/// 1. `isInline` replaces a `textContent` / `textFilename` / `isTruncated` triple.
///    Three overlapping answers to "how big is this" meant a truncated clip could
///    silently lose its tail. The rule is now single-valued: text up to
///    ``inlineByteLimit`` lives in `inlineText`, anything larger lives in a blob,
///    and nothing is ever discarded.
/// 2. `contentHash` is a real SHA-256 — see ``ContentHash``.
/// 3. `sourceBundleID` sits alongside the display name, so `app:` searches survive
///    a rename and icons resolve from a stable key.
struct ClipRecord: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {

    static let databaseTableName = "clip"

    /// Text at or below this many UTF-8 bytes is stored in the row itself.
    ///
    /// 8 KB comfortably covers the overwhelming majority of copied text while
    /// keeping the table small enough that a page of 200 rows is one cheap read.
    static let inlineByteLimit = 8 * 1024

    /// Longest precomputed preview. Enough for the tallest card, short enough that
    /// selecting a page never drags a novel out of the database.
    static let previewLimit = 240

    var id: String
    var kind: ClipKind
    /// Seconds since 1970 — *not* Apple's reference date. The previous app stored
    /// reference-date doubles, and the two epochs differ by 31 years, so the
    /// importer converts rather than copies.
    var createdAt: Double
    var sourceBundleID: String?
    var sourceAppName: String?
    var preview: String
    var contentHash: String
    var byteSize: Int
    var charCount: Int
    var isInline: Bool
    var inlineText: String?
    var blobKey: String?
    var thumbKey: String?
    /// Blob keys for the same text in richer formats, when the source app
    /// offered them. Both nil for plain text, which is most clips.
    var rtfKey: String?
    var htmlKey: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var recognizedText: String?
    var recognizedAt: Double?
    /// JSON holding pins, bookmarks and tags carried over from the previous app.
    /// Nothing reads it yet; it exists so an import is lossless and a later
    /// version can restore those features without a second migration.
    var legacyFlags: String?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case createdAt = "created_at"
        case sourceBundleID = "source_bundle_id"
        case sourceAppName = "source_app_name"
        case preview
        case contentHash = "content_hash"
        case byteSize = "byte_size"
        case charCount = "char_count"
        case isInline = "is_inline"
        case inlineText = "inline_text"
        case blobKey = "blob_key"
        case thumbKey = "thumb_key"
        case rtfKey = "rtf_key"
        case htmlKey = "html_key"
        case pixelWidth = "pixel_width"
        case pixelHeight = "pixel_height"
        case recognizedText = "recognized_text"
        case recognizedAt = "recognized_at"
        case legacyFlags = "legacy_flags"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let kind = Column(CodingKeys.kind)
        static let createdAt = Column(CodingKeys.createdAt)
        static let sourceBundleID = Column(CodingKeys.sourceBundleID)
        static let sourceAppName = Column(CodingKeys.sourceAppName)
        static let preview = Column(CodingKeys.preview)
        static let contentHash = Column(CodingKeys.contentHash)
        static let blobKey = Column(CodingKeys.blobKey)
        static let thumbKey = Column(CodingKeys.thumbKey)
        static let rtfKey = Column(CodingKeys.rtfKey)
        static let htmlKey = Column(CodingKeys.htmlKey)
        static let recognizedText = Column(CodingKeys.recognizedText)
        static let recognizedAt = Column(CodingKeys.recognizedAt)
    }

    var createdDate: Date { Date(timeIntervalSince1970: createdAt) }

    var source: SourceApp { SourceApp(bundleID: sourceBundleID, name: sourceAppName) }

    /// A clip whose bytes live outside the row, and so needs the blob store to be
    /// readable at all.
    var isBlobBacked: Bool { blobKey != nil }

    /// Every blob this clip refers to. The launch sweep asks each row for this,
    /// so a format added later cannot be forgotten and collected out from under
    /// a live clip.
    var referencedBlobKeys: [String] { [blobKey, rtfKey, htmlKey].compactMap { $0 } }
}

// MARK: - Construction

extension ClipRecord {

    /// Builds a text clip, spilling to a blob only when it exceeds
    /// ``inlineByteLimit``.
    ///
    /// The overflow path is a closure rather than a `BlobStore` parameter so this
    /// stays a pure value transformation for anything small — which, in practice,
    /// is nearly everything — and touches the disk only when it genuinely must.
    static func text(
        _ string: String,
        source: SourceApp = SourceApp(),
        at date: Date = Date(),
        id: String = UUID().uuidString,
        rtfKey: String? = nil,
        htmlKey: String? = nil,
        overflow: (Data) throws -> String
    ) rethrows -> ClipRecord {
        let data = Data(string.utf8)
        let inline = data.count <= inlineByteLimit
        return ClipRecord(
            id: id,
            kind: .text,
            createdAt: date.timeIntervalSince1970,
            sourceBundleID: source.bundleID,
            sourceAppName: source.name,
            preview: makePreview(from: string),
            contentHash: ContentHash.hex(of: data),
            byteSize: data.count,
            charCount: string.count,
            isInline: inline,
            inlineText: inline ? string : nil,
            blobKey: inline ? nil : try overflow(data),
            thumbKey: nil,
            rtfKey: rtfKey,
            htmlKey: htmlKey,
            pixelWidth: nil,
            pixelHeight: nil,
            recognizedText: nil,
            recognizedAt: nil,
            legacyFlags: nil
        )
    }

    /// Builds an image clip. Images always live in a blob; `preview` stays empty
    /// because there is no text to show — what makes an image findable is its
    /// `recognizedText`, filled in later by the recogniser.
    static func image(
        blobKey: String,
        thumbKey: String?,
        contentHash: String,
        byteSize: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        source: SourceApp = SourceApp(),
        at date: Date = Date(),
        id: String = UUID().uuidString
    ) -> ClipRecord {
        ClipRecord(
            id: id,
            kind: .image,
            createdAt: date.timeIntervalSince1970,
            sourceBundleID: source.bundleID,
            sourceAppName: source.name,
            preview: "",
            contentHash: contentHash,
            byteSize: byteSize,
            charCount: 0,
            isInline: false,
            inlineText: nil,
            blobKey: blobKey,
            thumbKey: thumbKey,
            rtfKey: nil,
            htmlKey: nil,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            recognizedText: nil,
            recognizedAt: nil,
            legacyFlags: nil
        )
    }

    /// A compact but faithful excerpt, capped at ``previewLimit``.
    ///
    /// Precomputed at capture rather than derived in `body`: a card that has to
    /// normalise a 2 MB string to draw three lines is a dropped frame every time
    /// it scrolls into view.
    ///
    /// Line structure and indentation are kept. Flattening everything to one
    /// line makes the cheapest thing a card can be — a readable snippet of code —
    /// unreadable, and indentation is most of what tells you at a glance which
    /// snippet you are looking at. What does get normalised is only noise: a run
    /// of blank lines becomes one, trailing spaces go, and a wall of alignment
    /// spaces is bounded so it cannot eat the whole budget.
    static func makePreview(from string: String) -> String {
        // Bounded work whatever the input: nothing past this could survive the
        // cap even if every character of it were kept.
        let sample = string.prefix(previewLimit * 4)

        var preview = ""
        preview.reserveCapacity(previewLimit + 1)
        var gap = ""

        for character in sample {
            // Before the whitespace test, because a newline is whitespace too —
            // and because `\r\n` is a single Swift Character, so this counts a
            // Windows line ending once rather than turning every line of Windows
            // text into a blank line between two.
            if character.isNewline {
                gap.append("\n")
                continue
            }
            if character.isWhitespace {
                gap.append(character)
                continue
            }
            // Whitespace before the first real character is indentation of
            // nothing, so it is dropped rather than normalised.
            if !preview.isEmpty {
                preview += normalizedGap(gap)
            }
            gap = ""
            preview.append(character)
            if preview.count >= previewLimit { break }
        }

        // `gap` is deliberately never flushed, which is what trims the trailing
        // whitespace of the excerpt and of its last line.
        return preview.count > previewLimit
            ? String(preview.prefix(previewLimit))
            : preview
    }

    private static func normalizedGap(_ run: String) -> String {
        guard let lastBreak = run.lastIndex(of: "\n") else {
            // Interior spacing, kept so aligned columns survive, but bounded.
            return String(run.prefix(8))
        }
        let breaks = run.count { $0 == "\n" }
        let indent = run[run.index(after: lastBreak)...]
        return String(repeating: "\n", count: min(breaks, 2)) + indent.prefix(16)
    }
}
