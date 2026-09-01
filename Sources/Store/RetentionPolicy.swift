import Foundation

/// How much history to keep.
///
/// Both limits are optional and independent: a clip is dropped if it falls
/// outside *either*. `nil` on both means the history grows forever, which is a
/// legitimate choice now that clips live in SQLite rather than in a JSON file
/// rewritten on every keystroke.
struct RetentionPolicy: Equatable, Sendable {

    /// Keep at most this many clips, newest first.
    var maximumCount: Int?

    /// Drop clips older than this.
    var maximumAge: TimeInterval?

    init(maximumCount: Int? = nil, maximumAge: TimeInterval? = nil) {
        self.maximumCount = maximumCount
        self.maximumAge = maximumAge
    }

    /// 2,000 clips and no age limit.
    ///
    /// The app this replaces capped at 1,000 because every mutation rewrote the
    /// whole history file, so the cap was really a write-cost ceiling. Paging out
    /// of an indexed table has no such ceiling; 2,000 is a storage decision now,
    /// and the number to revisit is whichever one Instruments dislikes.
    static let `default` = RetentionPolicy(maximumCount: 2_000, maximumAge: nil)

    static let unlimited = RetentionPolicy()

    var isUnlimited: Bool { maximumCount == nil && maximumAge == nil }
}
