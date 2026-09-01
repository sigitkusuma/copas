import AppKit
import Foundation

/// Application icons, resolved once and kept.
///
/// `NSWorkspace.icon(forFile:)` reads a bundle off disk. Called from `body` it is
/// called again on every redraw of every card, which is exactly the shape of
/// stall that makes a scrolling list feel broken. Cards only ever read from the
/// dictionary; filling it is somebody else's job, done once per load.
@MainActor
final class AppIconCache {

    static let shared = AppIconCache()

    private var icons: [String: NSImage] = [:]
    private var missing: Set<String> = []

    private init() {}

    /// A pure dictionary read. Safe in `body`; returns `nil` when nothing has
    /// resolved this identifier yet, which is the card's cue to draw a
    /// placeholder rather than to go looking.
    func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        return icons[bundleID]
    }

    /// Resolves anything not already known. Called after a load, off `body`.
    func prewarm(_ bundleIDs: some Sequence<String>) {
        for bundleID in Set(bundleIDs) where icons[bundleID] == nil && !missing.contains(bundleID) {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                // Remembered, so an app that has been uninstalled is not looked
                // up again on every single load.
                missing.insert(bundleID)
                continue
            }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            icons[bundleID] = icon
        }
    }
}
