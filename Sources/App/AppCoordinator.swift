import AppKit
import SwiftUI

/// Owns every long-lived object in the app and wires them together.
///
/// Deliberately the only place that knows how the pieces fit. Collaborators are
/// injected downward and hold references to each other only where the data
/// actually flows — there is no shared store singleton and no
/// `NotificationCenter` string-name bus for app-internal signalling, both of
/// which make call graphs impossible to follow once there are more than three
/// participants.
@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {

    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(
            onToggleBoard: { [weak self] in self?.toggleBoard() },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Actions

    private func toggleBoard() {
        // Phase 3 replaces this with BoardWindowController.
        NSSound.beep()
    }

    private func openSettings() {
        // The selector moved in macOS 14; the older one silently does nothing.
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
