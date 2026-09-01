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

    /// Formatted by the board's shared clock, not by the card.
    ///
    /// A card that formatted its own would have to observe the clock, and then
    /// every tick would invalidate every card. Holding the finished string here
    /// means a tick changes only the cards whose text actually changed — which,
    /// a minute in, is none of them.
    var timestamp: String

    init(_ record: ClipRecord, now: Date) {
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
            sections[sections.count - 1].cards.append(ClipCardModel(record, now: now))
        }

        return sections
    }
}
