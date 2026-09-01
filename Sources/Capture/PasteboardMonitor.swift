import AppKit
import Foundation

/// Watches the system pasteboard and reports what appears on it.
///
/// Holds no repository and no database. It produces values and stops there,
/// which is what lets it be driven by hand in a test — ``checkForChanges()`` is
/// the whole of its behaviour, and the poll loop only decides when to call it.
@MainActor
final class PasteboardMonitor {

    let payloads: AsyncStream<CapturedPayload>

    var reader: PasteboardReader

    private let pasteboard: NSPasteboard
    private let interval: Duration
    private let continuation: AsyncStream<CapturedPayload>.Continuation

    private var pollTask: Task<Void, Never>?
    private var lastChangeCount: Int
    private var suppressedUpTo = 0

    private(set) var isPaused = false

    init(
        pasteboard: NSPasteboard = .general,
        interval: Duration = .milliseconds(250),
        reader: PasteboardReader = PasteboardReader()
    ) {
        self.pasteboard = pasteboard
        self.interval = interval
        self.reader = reader
        // Start from wherever the pasteboard already is. Capturing at launch
        // would re-add whatever was copied before the app started, on every
        // launch, and date it as though it had just happened.
        self.lastChangeCount = pasteboard.changeCount

        let (stream, continuation) = AsyncStream.makeStream(of: CapturedPayload.self)
        self.payloads = stream
        self.continuation = continuation
    }

    deinit {
        continuation.finish()
    }

    // MARK: - Running

    /// Polls, rather than observing, because macOS has no pasteboard change
    /// notification — `changeCount` is the only signal there is. Each tick is a
    /// single integer read; the contents are only touched when that number moves,
    /// so the cost is per copy, not per tick.
    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkForChanges()
                do {
                    try await Task.sleep(for: self?.interval ?? .milliseconds(250))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
        // Anything copied while paused stays uncaptured rather than arriving all
        // at once, dated now, the moment capture resumes.
        lastChangeCount = pasteboard.changeCount
    }

    /// Tells the monitor to disregard everything up to and including a change
    /// count it caused itself.
    ///
    /// This replaces the "ignore the next change" flag the app this succeeds
    /// used, which was set by a notification and consumed by the next poll. Copy
    /// something in the gap between those two and it was silently dropped. A
    /// change count is not a race: it identifies the exact write to skip, and
    /// anything the user does afterwards has a strictly higher number.
    func suppress(upTo changeCount: Int) {
        suppressedUpTo = max(suppressedUpTo, changeCount)
    }

    /// One poll. Returns what it captured, for tests; the app reads ``payloads``.
    @discardableResult
    func checkForChanges(at date: Date = Date()) -> CapturedPayload? {
        guard !isPaused else { return nil }

        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return nil }

        // A pasteboard with no types at all is one that is being written to
        // right now: `clearContents()` bumps the change count and the data
        // arrives afterwards — microseconds later for a string, but a good deal
        // longer for an app that renders an image before writing it. Advancing
        // past that would drop the copy permanently, because the change count
        // never comes round again. Leaving it alone costs one more poll.
        guard pasteboard.types?.isEmpty == false else { return nil }

        lastChangeCount = changeCount

        guard changeCount > suppressedUpTo else { return nil }

        guard let payload = reader.read(
            pasteboard,
            source: PasteboardReader.frontmostApp(),
            at: date
        ) else { return nil }

        continuation.yield(payload)
        return payload
    }
}
