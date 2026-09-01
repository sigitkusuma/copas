import Foundation
import Observation
import ServiceManagement

/// Everything the user can change, in one place, backed by `UserDefaults`.
///
/// Owned by ``AppCoordinator`` and handed down, like everything else — there is
/// no shared settings singleton. That matters more here than elsewhere: a
/// settings object every layer can reach is a settings object every layer starts
/// reading directly, and then changing a default means auditing the whole app.
@MainActor
@Observable
final class Preferences {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        showBoardHotkey = Self.hotkey(forKey: Key.showBoardHotkey, in: defaults) ?? .showBoard
        captureToTextHotkey = Self.hotkey(forKey: Key.captureToTextHotkey, in: defaults) ?? .captureToText
        isCaptureToTextEnabled = defaults.object(forKey: Key.captureToTextEnabled) as? Bool ?? true

        boardEdge = (defaults.string(forKey: Key.boardEdge)).flatMap(BoardEdge.init(rawValue:)) ?? .top

        maximumClipCount = defaults.object(forKey: Key.maximumClipCount) as? Int
            ?? RetentionPolicy.default.maximumCount ?? 0
        maximumClipAgeInDays = defaults.object(forKey: Key.maximumClipAgeInDays) as? Int ?? 0

        excludedBundleIDs = defaults.stringArray(forKey: Key.excludedBundleIDs) ?? []

        recognizesTextInImages = defaults.object(forKey: Key.recognizesTextInImages) as? Bool ?? true
        copiesImageWhenNoTextFound = defaults.object(forKey: Key.copiesImageWhenNoTextFound) as? Bool ?? true
    }

    // MARK: - Shortcuts

    var showBoardHotkey: KeyCombination {
        didSet { write(showBoardHotkey, forKey: Key.showBoardHotkey) }
    }

    var captureToTextHotkey: KeyCombination {
        didSet { write(captureToTextHotkey, forKey: Key.captureToTextHotkey) }
    }

    var isCaptureToTextEnabled: Bool {
        didSet { defaults.set(isCaptureToTextEnabled, forKey: Key.captureToTextEnabled) }
    }

    // MARK: - Board

    var boardEdge: BoardEdge {
        didSet { defaults.set(boardEdge.rawValue, forKey: Key.boardEdge) }
    }

    // MARK: - History

    /// `0` means unlimited. Zero rather than an optional because that is what a
    /// stepper bound to a number can actually express.
    var maximumClipCount: Int {
        didSet { defaults.set(maximumClipCount, forKey: Key.maximumClipCount) }
    }

    var maximumClipAgeInDays: Int {
        didSet { defaults.set(maximumClipAgeInDays, forKey: Key.maximumClipAgeInDays) }
    }

    var retention: RetentionPolicy {
        RetentionPolicy(
            maximumCount: maximumClipCount > 0 ? maximumClipCount : nil,
            maximumAge: maximumClipAgeInDays > 0
                ? TimeInterval(maximumClipAgeInDays) * 86_400
                : nil
        )
    }

    /// Apps whose copies are never recorded.
    ///
    /// By bundle identifier, so an app the user excluded stays excluded when it
    /// is renamed, updated or localised.
    var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: Key.excludedBundleIDs) }
    }

    func exclude(_ bundleID: String) {
        guard !excludedBundleIDs.contains(bundleID) else { return }
        excludedBundleIDs.append(bundleID)
    }

    func include(_ bundleID: String) {
        excludedBundleIDs.removeAll { $0 == bundleID }
    }

    // MARK: - Recognition

    var recognizesTextInImages: Bool {
        didSet { defaults.set(recognizesTextInImages, forKey: Key.recognizesTextInImages) }
    }

    var copiesImageWhenNoTextFound: Bool {
        didSet { defaults.set(copiesImageWhenNoTextFound, forKey: Key.copiesImageWhenNoTextFound) }
    }

    // MARK: - Login item

    /// Not stored here. `SMAppService` keeps the real answer, and a copy in
    /// `UserDefaults` would disagree with it the moment the user changes the
    /// switch in System Settings instead.
    var launchesAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Log.app.error("could not change the login item: \(error, privacy: .public)")
            }
        }
    }

    // MARK: - Storage

    private enum Key {
        static let showBoardHotkey = "hotkey.showBoard"
        static let captureToTextHotkey = "hotkey.captureToText"
        static let captureToTextEnabled = "hotkey.captureToText.enabled"
        static let boardEdge = "board.edge"
        static let maximumClipCount = "history.maximumCount"
        static let maximumClipAgeInDays = "history.maximumAgeInDays"
        static let excludedBundleIDs = "history.excludedBundleIDs"
        static let recognizesTextInImages = "recognition.automatic"
        static let copiesImageWhenNoTextFound = "recognition.copiesImageWhenNoTextFound"
    }

    private func write(_ combination: KeyCombination, forKey key: String) {
        guard let data = try? JSONEncoder().encode(combination) else { return }
        defaults.set(data, forKey: key)
    }

    private static func hotkey(forKey key: String, in defaults: UserDefaults) -> KeyCombination? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(KeyCombination.self, from: data)
    }
}
