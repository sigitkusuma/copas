import AppKit
import Foundation

/// Names for bundle identifiers, so a list of excluded apps reads as apps
/// rather than as reverse-DNS.
///
/// Resolved through `NSWorkspace`, which means an app that has since been
/// uninstalled has no name to give — in which case the identifier itself is
/// shown rather than an empty row, because the user should still be able to see
/// and remove it.
@MainActor
enum InstalledApps {

    static func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    /// Asks the user to pick an application, and returns its bundle identifier.
    ///
    /// A file picker rather than a list of running apps: the app you most want
    /// to exclude — a password manager — is often not running when you go
    /// looking for it, and picking it out of `/Applications` is unambiguous.
    static func chooseApplication() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Exclude"
        panel.message = "Copies made in this app will never be recorded."

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}
