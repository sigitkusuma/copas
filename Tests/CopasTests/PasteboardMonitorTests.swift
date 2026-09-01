import AppKit
import Foundation
import Testing

@testable import Copas

@MainActor
final class PasteboardMonitorTests {

    let pasteboard = Fixtures.pasteboard()
    let monitor: PasteboardMonitor

    init() {
        monitor = PasteboardMonitor(pasteboard: pasteboard)
    }

    deinit {
        pasteboard.releaseGlobally()
    }

    private func copy(_ string: String) -> Int {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        return pasteboard.changeCount
    }

    @Test func aNewCopyIsCaptured() {
        _ = copy("hello")
        #expect(monitor.checkForChanges()?.content == .text(RichText(plain: "hello")))
    }

    @Test func pollingWithoutACopyCapturesNothing() {
        _ = copy("hello")
        #expect(monitor.checkForChanges() != nil)
        #expect(monitor.checkForChanges() == nil)
        #expect(monitor.checkForChanges() == nil)
    }

    @Test func whateverWasAlreadyOnTheClipboardAtLaunchIsLeftAlone() {
        _ = copy("copied before we started")
        let fresh = PasteboardMonitor(pasteboard: pasteboard)
        #expect(fresh.checkForChanges() == nil)
    }

    /// The self-capture fix. The app this replaces set an "ignore the next
    /// change" flag and let the next poll consume it; a copy landing in that gap
    /// was silently dropped. A change count names the exact write to skip, so
    /// there is no gap to land in.
    @Test func theAppsOwnWriteIsSkipped() {
        let ours = copy("pasted by us")
        monitor.suppress(upTo: ours)

        #expect(monitor.checkForChanges() == nil)
    }

    @Test func aCopyAfterOurOwnWriteIsStillCaptured() {
        let ours = copy("pasted by us")
        monitor.suppress(upTo: ours)

        _ = copy("typed by the user")
        #expect(monitor.checkForChanges()?.content == .text(RichText(plain: "typed by the user")))
    }

    /// The case the old flag lost: the user copies between our write and the
    /// next poll, so the poll sees a change count higher than the one we
    /// suppressed and must still capture it.
    @Test func aCopyRacingOurOwnWriteIsNotSwallowed() {
        let ours = copy("pasted by us")
        _ = copy("copied a moment later")
        monitor.suppress(upTo: ours)

        #expect(monitor.checkForChanges()?.content == .text(RichText(plain: "copied a moment later")))
    }

    @Test func nothingIsCapturedWhilePaused() {
        monitor.pause()
        _ = copy("while paused")
        #expect(monitor.checkForChanges() == nil)
    }

    /// Resuming should not flush a backlog dated as though it all just happened.
    @Test func resumingDoesNotReplayWhatWasCopiedWhilePaused() {
        monitor.pause()
        _ = copy("while paused")
        monitor.resume()

        #expect(monitor.checkForChanges() == nil)

        _ = copy("after resuming")
        #expect(monitor.checkForChanges()?.content == .text(RichText(plain: "after resuming")))
    }

    @Test func capturedPayloadsReachTheStream() async {
        _ = copy("through the stream")
        var iterator = monitor.payloads.makeAsyncIterator()
        monitor.checkForChanges()

        let payload = await iterator.next()
        #expect(payload?.content == .text(RichText(plain: "through the stream")))
    }
}
