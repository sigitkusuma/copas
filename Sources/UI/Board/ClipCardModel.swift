import Foundation

/// Everything one card draws, and nothing else.
///
/// The cards are fed this rather than a `ClipRecord` on purpose. A record
/// carries content, hashes and blob keys that no card looks at, and comparing
/// those is what makes a whole board redraw when a single thing changed. This is
/// small, `Equatable`, and changes only when something visible does — which is
/// what lets ``ClipCard`` be an `EquatableView` and mean it.
struct ClipCardModel: Identifiable, Equatable, Sendable {

    let id: String
    let kind: ClipKind
    let preview: String
    let createdAt: Date
    let sourceBundleID: String?
    let sourceName: String?
    let thumbnailKey: String?
    let recognizedText: String?
    let byteSize: Int
    let charCount: Int
    /// `nil` when the text lives in a blob and counting would mean reading it.
    let lineCount: Int?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let isMonospaced: Bool

    /// What the card actually draws, which is not always the preview — see the
    /// initialiser.
    let displayText: String
    /// The clip flattened to one run of text, for a list row two lines tall.
    ///
    /// Collapsed once here rather than in the row: the pass over the text
    /// happens when the section is built instead of on every redraw, and a
    /// snippet of code arrives in the list as two lines of content rather than
    /// as one visible line above an empty one.
    let listTitle: String
    /// The recognised-text caption under an image, excerpted around the match
    /// when there is one.
    let recognizedCaption: String?
    /// Why this clip is in the results, when the reason is not the preview.
    let matchSource: MatchSource
    /// The words to mark in ``displayText`` and ``recognizedCaption``.
    let terms: [String]

    /// Formatted by the board's shared clock, not by the card.
    ///
    /// A card that formatted its own would have to observe the clock, and then
    /// every tick would invalidate every card. Holding the finished string here
    /// means a tick changes only the cards whose text actually changed — which,
    /// a minute in, is none of them.
    var timestamp: String

    /// Where a search found this clip, when the card would not otherwise show it.
    enum MatchSource: Equatable, Sendable {
        case none
        /// Past the 240 characters the preview holds.
        case body
        /// Inside the text read out of a picture.
        case recognizedText
    }

    init(_ record: ClipRecord, now: Date, terms: [String] = []) {
        id = record.id
        kind = record.kind
        preview = record.preview
        createdAt = record.createdDate
        sourceBundleID = record.sourceBundleID
        sourceName = record.sourceAppName
        thumbnailKey = record.thumbKey
        recognizedText = record.recognizedText
        byteSize = record.byteSize
        charCount = record.charCount
        lineCount = record.inlineText.map { text in text.count { $0 == "\n" } + 1 }
        pixelWidth = record.pixelWidth
        pixelHeight = record.pixelHeight
        isMonospaced = record.kind == .text && CodeHeuristic.looksLikeCode(record.preview)
        timestamp = RelativeTime.string(for: record.createdDate, relativeTo: now)
        self.terms = terms

        // A search can find a clip somewhere the card is not showing: past the
        // 240 characters of the preview, or inside text read out of a picture.
        // Leaving the card as it was returns a result with no visible reason to
        // be there, which reads as the search being wrong.
        if terms.isEmpty || SearchHighlight.matches(terms, in: record.preview) {
            matchSource = .none
            displayText = record.preview
        } else if
            let inline = record.inlineText,
            let excerpt = SearchHighlight.excerpt(from: inline, matching: terms)
        {
            matchSource = .body
            displayText = excerpt
        } else if
            let recognized = record.recognizedText,
            SearchHighlight.matches(terms, in: recognized)
        {
            matchSource = .recognizedText
            displayText = record.preview
        } else {
            matchSource = .none
            displayText = record.preview
        }

        if let recognized = record.recognizedText, !recognized.isEmpty {
            recognizedCaption = SearchHighlight.excerpt(from: recognized, matching: terms)
                ?? String(recognized.prefix(180))
        } else {
            recognizedCaption = nil
        }

        // An image clip has no preview text of its own, so the list shows what
        // was read out of it. Empty is a legitimate answer for both kinds, and
        // the row draws a placeholder rather than a blank line.
        switch record.kind {
        case .text: listTitle = Self.collapsed(displayText)
        case .image: listTitle = Self.collapsed(recognizedCaption ?? "")
        }
    }

    /// Runs of whitespace — including the newlines that make a code snippet a
    /// column — flattened to single spaces.
    ///
    /// Hand-rolled rather than a regular expression or `components(separatedBy:)`:
    /// this runs for every card in a five-hundred-row page on every keystroke,
    /// and one pass with no intermediate array is the difference between a
    /// keystroke that costs nothing and one that shows.
    static func collapsed(_ text: String, limit: Int = 200) -> String {
        var result = ""
        result.reserveCapacity(limit)

        // Counted rather than asked for: `String.count` walks the whole string,
        // and asking it once per character would turn a linear pass into a
        // quadratic one.
        var written = 0
        var pendingSpace = false

        for character in text {
            if character.isWhitespace {
                pendingSpace = written > 0
                continue
            }
            if pendingSpace {
                result.append(" ")
                written += 1
                pendingSpace = false
            }
            result.append(character)
            written += 1
            if written >= limit { break }
        }
        return result
    }

    /// What VoiceOver reads for this card.
    ///
    /// One sentence rather than the six separate fragments the card is built
    /// from. Left to itself, VoiceOver walks the app name, then the timestamp,
    /// then the snippet, then the footer as four unrelated items, which for a
    /// strip of two hundred cards is unusable. The card is one element, and this
    /// is what it says.
    var accessibilityDescription: String {
        var parts: [String] = []

        switch kind {
        case .text:
            parts.append(displayText.isEmpty ? "Empty text clip" : displayText)
        case .image:
            if let pixelWidth, let pixelHeight {
                parts.append("Image, \(pixelWidth) by \(pixelHeight) pixels")
            } else {
                parts.append("Image")
            }
            if let recognizedCaption, !recognizedCaption.isEmpty {
                parts.append("Text in image: \(recognizedCaption)")
            }
        }

        if let sourceName { parts.append("from \(sourceName)") }
        parts.append(timestamp == "now" ? "just now" : "\(timestamp) ago")

        switch matchSource {
        case .body: parts.append("matched inside the clip")
        case .recognizedText: parts.append("matched in the text of the image")
        case .none: break
        }

        return parts.joined(separator: ", ")
    }

    var hasRecognizedText: Bool {
        !(recognizedText ?? "").isEmpty
    }

    /// The footer line: what this clip is, in numbers.
    var detail: String {
        switch kind {
        case .text:
            let characters = "\(charCount.formatted()) character\(charCount == 1 ? "" : "s")"
            guard let lineCount, lineCount > 1 else { return characters }
            return "\(lineCount.formatted()) lines · \(characters)"

        case .image:
            guard let pixelWidth, let pixelHeight else { return Self.byteString(byteSize) }
            return "\(pixelWidth) × \(pixelHeight) · \(Self.byteString(byteSize))"
        }
    }

    /// Sizes without `ByteCountFormatter`, which allocates and is measurably
    /// expensive when a few hundred cards each want one string.
    static func byteString(_ bytes: Int) -> String {
        if bytes < 1_024 { return "\(bytes) B" }
        if bytes < 1_024 * 1_024 { return "\(bytes / 1_024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1_024 * 1_024))
    }
}

/// A day's worth of clips, which is how the strip is divided.
struct ClipSection: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    var cards: [ClipCardModel]
}

enum ClipSectionBuilder {

    /// Groups clips by the day they were captured, newest first.
    ///
    /// Relies on the records already being ordered — they come out of an indexed
    /// query that way — so this is one pass with no sorting.
    static func sections(
        from records: [ClipRecord],
        now: Date,
        terms: [String] = [],
        calendar: Calendar = .current
    ) -> [ClipSection] {
        var sections: [ClipSection] = []

        for record in records {
            let date = record.createdDate
            let day = calendar.startOfDay(for: date)
            let id = String(Int(day.timeIntervalSince1970))

            if sections.last?.id != id {
                sections.append(ClipSection(
                    id: id,
                    label: RelativeTime.dayLabel(for: date, relativeTo: now),
                    cards: []
                ))
            }
            sections[sections.count - 1].cards.append(ClipCardModel(record, now: now, terms: terms))
        }

        return sections
    }
}
