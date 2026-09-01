import Foundation

/// How long ago something was, in as few characters as a card can spare.
///
/// Hand-rolled rather than `RelativeDateTimeFormatter`, which allocates and
/// produces "3 minutes ago" where a card has room for "3m". Every card on the
/// board formats its own timestamp on each tick of the shared clock, so this has
/// to be cheap enough that doing it a few hundred times is not a thought.
enum RelativeTime {

    static func string(for date: Date, relativeTo now: Date) -> String {
        let seconds = now.timeIntervalSince(date)

        // A clip captured a moment *ahead* of the clock — a machine whose time
        // was corrected, or an import — should read as "now", not as a negative.
        guard seconds > 5 else { return "now" }

        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h" }
        if seconds < 604_800 { return "\(Int(seconds / 86_400))d" }

        return calendarDate(date, relativeTo: now)
    }

    private static func calendarDate(_ date: Date, relativeTo now: Date) -> String {
        let calendar = Calendar.current
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let formatter = sameYear ? dayAndMonth : dayMonthAndYear
        return formatter.string(from: date)
    }

    // Formatters are expensive to build and safe to reuse, so exactly one of each
    // exists for the life of the process.
    private static let dayAndMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()

    private static let dayMonthAndYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return formatter
    }()

    /// The heading a clip belongs under.
    static func dayLabel(for date: Date, relativeTo now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return calendarDate(date, relativeTo: now)
    }
}
