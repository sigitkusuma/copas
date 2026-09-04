import Foundation
import Testing

@testable import Copas

/// Serialized, and sharing one defaults suite.
///
/// A suite per test needs a unique name, and `UserDefaults` leaves an empty
/// plist in ~/Library/Preferences for every name it has ever seen — nothing
/// reaps them, and eighty-five had piled up before anyone went looking. One
/// suite, cleared either side of each test, leaves exactly one empty file
/// however many times this runs.
@MainActor
@Suite(.serialized)
final class PreferencesTests {

    static let suiteName = "com.sigitkusuma.copas.tests"
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: Self.suiteName))
        // Cleared going in as well as coming out, so a crashed run cannot leave
        // the next one reading somebody else's settings.
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    deinit {
        defaults.removePersistentDomain(forName: Self.suiteName)
    }

    private func make() -> Preferences {
        Preferences(defaults: defaults)
    }

    @Test func aFreshInstallGetsWorkingDefaults() {
        let preferences = make()

        #expect(preferences.showBoardHotkey == .showBoard)
        #expect(preferences.captureToTextHotkey == .captureToText)
        #expect(preferences.isCaptureToTextEnabled)
        #expect(preferences.boardEdge == .top)
        #expect(preferences.recognizesTextInImages)
        #expect(preferences.excludedBundleIDs.isEmpty)
        #expect(preferences.retention == RetentionPolicy.default)
        #expect(!preferences.hasCompletedWelcome)
    }

    /// The welcome window should show once, on the first launch after
    /// install, and never show itself again after that.
    @Test func welcomeIsNotShownAgainOnceCompleted() {
        let first = make()
        first.hasCompletedWelcome = true

        let second = make()
        #expect(second.hasCompletedWelcome)
    }

    @Test func changesSurviveARelaunch() {
        let first = make()
        first.showBoardHotkey = KeyCombination(keyCode: 0x08, modifiers: [.command, .control])
        first.boardEdge = .bottom
        first.maximumClipCount = 50
        first.recognizesTextInImages = false
        first.exclude("com.1password.1password")

        let second = make()
        #expect(second.showBoardHotkey == KeyCombination(keyCode: 0x08, modifiers: [.command, .control]))
        #expect(second.boardEdge == .bottom)
        #expect(second.maximumClipCount == 50)
        #expect(!second.recognizesTextInImages)
        #expect(second.excludedBundleIDs == ["com.1password.1password"])
    }

    /// Zero rather than an optional, because that is what a text field bound to
    /// a number can actually express — but it has to mean "no limit", not
    /// "keep nothing".
    @Test func zeroMeansUnlimitedRatherThanEmpty() {
        let preferences = make()
        preferences.maximumClipCount = 0
        preferences.maximumClipAgeInDays = 0

        #expect(preferences.retention.isUnlimited)
        #expect(preferences.retention.maximumCount == nil)
        #expect(preferences.retention.maximumAge == nil)
    }

    @Test func anAgeLimitIsCountedInDays() throws {
        let preferences = make()
        preferences.maximumClipAgeInDays = 7

        let age = try #require(preferences.retention.maximumAge)
        #expect(age == 604_800)
    }

    @Test func excludingAnAppTwiceListsItOnce() {
        let preferences = make()
        preferences.exclude("com.apple.Safari")
        preferences.exclude("com.apple.Safari")

        #expect(preferences.excludedBundleIDs == ["com.apple.Safari"])

        preferences.include("com.apple.Safari")
        #expect(preferences.excludedBundleIDs.isEmpty)
    }

    /// Off is the only safe default: somebody who has not asked for pre-release
    /// builds should never be handed one.
    @Test func betaUpdatesAreOffUntilAskedFor() {
        let preferences = make()
        #expect(preferences.checksForUpdatesAutomatically)
        #expect(!preferences.receivesBetaUpdates)
    }

    @Test func updateChoicesSurviveARelaunch() {
        let first = make()
        first.checksForUpdatesAutomatically = false
        first.receivesBetaUpdates = true

        let second = make()
        #expect(!second.checksForUpdatesAutomatically)
        #expect(second.receivesBetaUpdates)
    }

    /// Preferences that survive a relaunch have to survive being written down,
    /// and a shortcut is the only thing here that is not a plain value.
    @Test func aShortcutRoundTripsThroughStorage() throws {
        let original = KeyCombination(keyCode: 0x2E, modifiers: [.command, .shift, .option, .control])
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeyCombination.self, from: encoded)

        #expect(decoded == original)
        #expect(decoded.displayString == "⌃⌥⇧⌘M")
    }

    /// Stored settings from a future version, or a corrupted domain, must not
    /// stop the app from starting with something sensible.
    @Test func unreadableStoredValuesFallBackToTheDefaults() {
        defaults.set("not a shortcut", forKey: "hotkey.showBoard")
        defaults.set("sideways", forKey: "board.edge")

        let preferences = make()
        #expect(preferences.showBoardHotkey == .showBoard)
        #expect(preferences.boardEdge == .top)
    }
}
