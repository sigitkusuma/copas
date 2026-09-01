import AppKit
import Foundation

/// Everything to put back on the pasteboard for one clip, in preference order.
///
/// Types are plain strings so this stays a `Sendable` value that a test can
/// assert on without an `NSPasteboard` in the room.
struct PasteboardSnapshot: Sendable, Equatable {

    struct Representation: Sendable, Equatable {
        var type: String
        var data: Data
    }

    /// Richest first. Receiving apps take the first type they understand, so the
    /// order here is what decides whether a paste into Pages keeps its bold and
    /// a paste into a terminal stays plain.
    var representations: [Representation]

    var isEmpty: Bool { representations.isEmpty }

    static func text(_ plain: String, rtf: Data? = nil, html: Data? = nil) -> PasteboardSnapshot {
        var representations: [Representation] = []
        if let rtf { representations.append(Representation(type: NSPasteboard.PasteboardType.rtf.rawValue, data: rtf)) }
        if let html { representations.append(Representation(type: NSPasteboard.PasteboardType.html.rawValue, data: html)) }
        representations.append(Representation(
            type: NSPasteboard.PasteboardType.string.rawValue,
            data: Data(plain.utf8)
        ))
        return PasteboardSnapshot(representations: representations)
    }

    static func image(_ data: Data, isPNG: Bool = true) -> PasteboardSnapshot {
        PasteboardSnapshot(representations: [
            Representation(
                type: (isPNG ? NSPasteboard.PasteboardType.png : .tiff).rawValue,
                data: data
            )
        ])
    }

    /// Writes to a pasteboard and returns the change count the write produced.
    ///
    /// That number is the whole point: handed to
    /// ``PasteboardMonitor/suppress(upTo:)`` it identifies exactly this write, so
    /// the app never records its own paste as a new clip.
    @discardableResult
    func write(to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        for representation in representations {
            pasteboard.setData(
                representation.data,
                forType: NSPasteboard.PasteboardType(representation.type)
            )
        }
        return pasteboard.changeCount
    }
}
