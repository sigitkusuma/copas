import AppKit
import ApplicationServices
import Foundation

enum PasteError: Error, Equatable {
    /// The clip's bytes are not where the row says they are — a blob deleted
    /// out from under it, or a store that failed to open.
    case contentUnavailable
    /// Synthesising a keystroke needs Accessibility. Without it the event is
    /// posted and silently ignored, which reads to the user as the app being
    /// broken rather than as a permission being missing.
    case notTrustedForAccessibility
}

/// Puts a clip back on the pasteboard, and optionally presses ⌘V for you.
@MainActor
final class Paster {

    private let pasteboard: NSPasteboard
    private let blobs: BlobStore

    init(pasteboard: NSPasteboard = .general, blobs: BlobStore) {
        self.pasteboard = pasteboard
        self.blobs = blobs
    }

    /// Copies without pasting. Returns the change count of this write.
    @discardableResult
    func copy(_ record: ClipRecord) throws -> Int {
        try snapshot(for: record).write(to: pasteboard)
    }

    /// Presses ⌘V into whichever app should receive it.
    ///
    /// Deliberately separate from ``copy(_:)`` rather than one `paste` call.
    /// The caller needs the change count from the write *before* the keystroke
    /// lands, so it can tell the monitor to ignore it — and if Accessibility is
    /// missing, a clip already sitting on the pasteboard that the user can paste
    /// by hand is a far better outcome than an operation that unwound itself.
    func pressCommandV(into app: NSRunningApplication? = nil) throws {
        guard Self.isTrustedForAccessibility else {
            throw PasteError.notTrustedForAccessibility
        }

        if let app {
            app.activate()
        }

        // The keystroke has to arrive after the receiving app is actually
        // frontmost, and activation is asynchronous. Nothing to wait for when we
        // never took focus in the first place.
        let settle: Duration = app == nil ? .milliseconds(20) : .milliseconds(120)
        Task { @MainActor in
            try? await Task.sleep(for: settle)
            Self.synthesizeCommandV()
        }
    }

    // MARK: - Content

    func snapshot(for record: ClipRecord) throws -> PasteboardSnapshot {
        switch record.kind {
        case .text:
            let plain: String
            if record.isInline {
                guard let inline = record.inlineText else { throw PasteError.contentUnavailable }
                plain = inline
            } else {
                guard
                    let key = record.blobKey,
                    let data = try? blobs.data(for: key),
                    let text = String(data: data, encoding: .utf8)
                else { throw PasteError.contentUnavailable }
                plain = text
            }

            return .text(
                plain,
                rtf: record.rtfKey.flatMap { try? blobs.data(for: $0) },
                html: record.htmlKey.flatMap { try? blobs.data(for: $0) }
            )

        case .image:
            guard let key = record.blobKey, let data = try? blobs.data(for: key) else {
                throw PasteError.contentUnavailable
            }
            return .image(data)
        }
    }

    // MARK: - Accessibility

    static var isTrustedForAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Asks the system to show the Accessibility prompt. Shows it once per
    /// install; afterwards it is a silent no-op and the user has to go to
    /// System Settings themselves, which is why the caller needs to say so too.
    @discardableResult
    static func requestAccessibilityTrust() -> Bool {
        // The key is spelled out rather than read from
        // `kAXTrustedCheckOptionPrompt`, which imports as a mutable global and so
        // is not concurrency-safe to touch. Its value is this string and has been
        // since the API shipped.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func synthesizeCommandV() {
        // 0x09 is `V` on every layout: virtual key codes are positional, so this
        // is the same physical key on AZERTY and Dvorak, which is what ⌘V means.
        let v: CGKeyCode = 0x09
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand

        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
