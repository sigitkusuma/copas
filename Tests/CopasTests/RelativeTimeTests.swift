import Foundation
import Testing

@testable import Copas

struct RelativeTimeTests {

    static let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func ago(_ seconds: TimeInterval) -> String {
        RelativeTime.string(for: Self.now.addingTimeInterval(-seconds), relativeTo: Self.now)
    }

    @Test func recentClipsReadAsNow() {
        #expect(ago(0) == "now")
        #expect(ago(4) == "now")
    }

    @Test func theUnitGrowsWithTheAge() {
        #expect(ago(30) == "30s")
        #expect(ago(90) == "1m")
        #expect(ago(3_600 * 5) == "5h")
        #expect(ago(86_400 * 3) == "3d")
    }

    @Test func theBoundariesLandOnTheLargerUnit() {
        #expect(ago(59) == "59s")
        #expect(ago(60) == "1m")
        #expect(ago(3_599) == "59m")
        #expect(ago(3_600) == "1h")
        #expect(ago(86_399) == "23h")
        #expect(ago(86_400) == "1d")
    }

    /// A clip stamped slightly ahead of the clock — a machine whose time was
    /// corrected, or an import — should read as "now", never as a negative.
    @Test func aClipFromTheFutureStillReadsAsNow() {
        #expect(RelativeTime.string(for: Self.now.addingTimeInterval(600), relativeTo: Self.now) == "now")
    }

    @Test func anythingOlderThanAWeekGetsADate() {
        let old = ago(86_400 * 30)
        #expect(!old.hasSuffix("d"))
        let namesAMonth = old.contains(where: \.isLetter)
        #expect(namesAMonth)
    }

    @Test func todayAndYesterdayAreNamed() {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Self.now)!

        #expect(RelativeTime.dayLabel(for: Self.now, relativeTo: Self.now) == "Today")
        #expect(RelativeTime.dayLabel(for: yesterday, relativeTo: Self.now) == "Yesterday")

        let lastWeek = calendar.date(byAdding: .day, value: -8, to: Self.now)!
        let label = RelativeTime.dayLabel(for: lastWeek, relativeTo: Self.now)
        #expect(label != "Today" && label != "Yesterday")
    }
}
