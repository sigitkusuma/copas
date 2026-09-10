import Foundation

/// Represents an application's clip contribution in the history.
public struct AppClipCount: Identifiable, Sendable, Equatable {
    public var id: String { bundleID ?? name }
    public let bundleID: String?
    public let name: String
    public let count: Int

    public init(bundleID: String?, name: String, count: Int) {
        self.bundleID = bundleID
        self.name = name
        self.count = count
    }
}

/// Aggregate statistics across the user's stored clipboard history.
public struct ClipboardStats: Sendable, Equatable {
    public var totalClips: Int
    public var textClips: Int
    public var imageClips: Int
    public var pinnedClips: Int
    public var clipsToday: Int
    public var clipsThisWeek: Int
    public var totalBytes: Int
    public var topApps: [AppClipCount]

    public init(
        totalClips: Int = 0,
        textClips: Int = 0,
        imageClips: Int = 0,
        pinnedClips: Int = 0,
        clipsToday: Int = 0,
        clipsThisWeek: Int = 0,
        totalBytes: Int = 0,
        topApps: [AppClipCount] = []
    ) {
        self.totalClips = totalClips
        self.textClips = textClips
        self.imageClips = imageClips
        self.pinnedClips = pinnedClips
        self.clipsToday = clipsToday
        self.clipsThisWeek = clipsThisWeek
        self.totalBytes = totalBytes
        self.topApps = topApps
    }

    /// Formatted human-readable storage footprint (e.g. "1.2 MB").
    public var formattedStorageSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(totalBytes))
    }
}
