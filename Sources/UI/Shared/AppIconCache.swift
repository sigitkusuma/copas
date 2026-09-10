import AppKit
import Foundation
import Observation

/// Application icons, resolved asynchronously and cached in memory.
///
/// `NSWorkspace.urlForApplication` and `NSWorkspace.icon(forFile:)` perform disk I/O
/// and system IPC with LaunchServices (`lsd`). For duplicated or slow bundles,
/// LaunchServices can block for up to 60+ seconds. Resolving icons must ALWAYS
/// happen off the main thread so the UI never hitches or freezes.
@Observable
@MainActor
final class AppIconCache {

    static let shared = AppIconCache()

    private(set) var icons: [String: NSImage] = [:]
    @ObservationIgnored private var missing: Set<String> = []
    @ObservationIgnored private var inFlight: Set<String> = []

    private init() {}

    /// A pure dictionary read. Safe in `body`; returns `nil` when nothing has
    /// resolved this identifier yet, which is the card's cue to draw a
    /// placeholder rather than to go looking.
    func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let icon = icons[bundleID] {
            return icon
        }
        if !missing.contains(bundleID) && !inFlight.contains(bundleID) {
            prewarm([bundleID])
        }
        return nil
    }

    /// Resolves anything not already known off the main thread.
    func prewarm(_ bundleIDs: some Sequence<String>) {
        let needed = Set(bundleIDs).filter {
            icons[$0] == nil && !missing.contains($0) && !inFlight.contains($0)
        }
        guard !needed.isEmpty else { return }

        for id in needed {
            inFlight.insert(id)
        }

        Task.detached(priority: .utility) {
            for bundleID in needed {
                var resolvedIcon: NSImage? = nil

                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                    let icon = NSWorkspace.shared.icon(forFile: url.path)
                    icon.size = NSSize(width: 16, height: 16)
                    resolvedIcon = icon
                }

                await MainActor.run {
                    AppIconCache.shared.inFlight.remove(bundleID)
                    if let resolvedIcon {
                        AppIconCache.shared.icons[bundleID] = resolvedIcon
                    } else {
                        AppIconCache.shared.missing.insert(bundleID)
                    }
                }
            }
        }
    }
}

