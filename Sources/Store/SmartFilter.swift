import Foundation

/// One-tap filter categories displayed as pills under the search bar and usable
/// in queries.
public enum SmartFilter: String, CaseIterable, Identifiable, Sendable, Equatable {
    case all = "All"
    case pinned = "Pinned"
    case links = "Links"
    case code = "Code"
    case images = "Images"
    case colors = "Colors"

    public var id: String { rawValue }

    public var label: String { rawValue }

    public var icon: String {
        switch self {
        case .all: return "tray.full"
        case .pinned: return "pin.fill"
        case .links: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .images: return "photo"
        case .colors: return "paintpalette"
        }
    }
}
