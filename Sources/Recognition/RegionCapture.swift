import AppKit
import CoreGraphics
import Foundation

/// Lets the user drag out a region of the screen.
///
/// Shells out to `/usr/sbin/screencapture` rather than drawing an overlay,
/// which buys the familiar macOS crosshair, its snapping, its space and window
/// selection, and its Escape-to-cancel — all of it behaviour people already know
/// and none of it worth reimplementing slightly differently.
@MainActor
final class RegionCapture {

    enum Outcome: Equatable {
        case captured(Data)
        /// Escape, or a click with no drag. Not an error, and not worth a HUD.
        case cancelled
        case failed
    }

    private var isCapturing = false

    /// Returns once the user has finished dragging, or given up.
    func selectRegion() async -> Outcome {
        // The crosshair is modal to the whole screen; a second one would fight
        // the first for the same drag.
        guard !isCapturing else { return .cancelled }
        isCapturing = true
        defer { isCapturing = false }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("copas-capture-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        guard await Self.run(writingTo: url) else { return .cancelled }
        guard let data = try? Data(contentsOf: url) else { return .failed }
        return .captured(data)
    }

    private static func run(writingTo url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                // -i interactive region, -x no shutter sound, -o no window shadow
                process.arguments = ["-i", "-x", "-o", url.path]

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    Log.app.error("could not start screencapture: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: false)
                    return
                }

                // Escape leaves a non-zero status and no file behind.
                let captured = process.terminationStatus == 0
                    && FileManager.default.fileExists(atPath: url.path)
                continuation.resume(returning: captured)
            }
        }
    }

    // MARK: - Permission

    /// Screen Recording is a separate grant from Accessibility, and it is only
    /// ever asked for when the user actually triggers a capture — a menu-bar app
    /// that demands screen access on first launch has not earned it yet.
    static var isPermitted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Asks, and explains where to go when asking is not enough.
    ///
    /// The system prompt appears at most once per install; afterwards the request
    /// is a silent no-op and the only way through is System Settings, which is
    /// why this says so rather than leaving the feature quietly dead.
    @discardableResult
    static func requestPermission() -> Bool {
        if isPermitted { return true }

        CGRequestScreenCaptureAccess()

        let alert = NSAlert()
        alert.messageText = "Copas needs Screen Recording access"
        alert.informativeText = """
            Capture to Text reads the region you select, so macOS asks for \
            Screen Recording access before it will hand over the pixels.

            Turn it on in System Settings › Privacy & Security › Screen Recording, \
            then try again.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }

        return false
    }
}
