import AppKit
import CoreGraphics
import Foundation

/// What can be drawn on a screenshot.
enum AnnotationKind: Equatable, Sendable {
    case rectangle
    case ellipse
    case text
    /// A translucent marker stroke over the area.
    case highlight
    /// Pixelates the area. Pixelation rather than a gaussian blur because a
    /// blur of small text can be partly read back, and the point of the tool is
    /// to hide it.
    case blur
}

/// A colour that can be compared and sent across threads, which `NSColor` cannot.
struct AnnotationColor: Equatable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    static let red = AnnotationColor(red: 0.93, green: 0.19, blue: 0.19)
    static let orange = AnnotationColor(red: 0.98, green: 0.55, blue: 0.10)
    static let yellow = AnnotationColor(red: 1.00, green: 0.84, blue: 0.10)
    static let green = AnnotationColor(red: 0.16, green: 0.72, blue: 0.34)
    static let blue = AnnotationColor(red: 0.10, green: 0.45, blue: 0.96)
    static let black = AnnotationColor(red: 0.05, green: 0.05, blue: 0.05)
    static let white = AnnotationColor(red: 1, green: 1, blue: 1)

    static let palette: [AnnotationColor] = [.red, .orange, .yellow, .green, .blue, .black, .white]
}

/// One mark on the picture.
///
/// Everything is in the *image's* pixel space, origin top-left, never in view
/// coordinates. That is what lets the same marks be drawn into the editor at any
/// zoom and into the exported bitmap at any size without translating between
/// the two.
struct Annotation: Identifiable, Equatable, Sendable {
    let id: UUID
    var kind: AnnotationKind
    var rect: CGRect
    var color: AnnotationColor
    var lineWidth: CGFloat
    var text: String
    var fontSize: CGFloat

    init(
        id: UUID = UUID(),
        kind: AnnotationKind,
        rect: CGRect,
        color: AnnotationColor = .red,
        lineWidth: CGFloat = 4,
        text: String = "",
        fontSize: CGFloat = 28
    ) {
        self.id = id
        self.kind = kind
        self.rect = rect.standardized
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.fontSize = fontSize
    }

    /// A label sized to fit its own text, anchored at `origin`.
    static func label(_ text: String, at origin: CGPoint, color: AnnotationColor, fontSize: CGFloat) -> Annotation {
        let size = textSize(text, fontSize: fontSize)
        return Annotation(
            kind: .text,
            rect: CGRect(origin: origin, size: size),
            color: color,
            text: text,
            fontSize: fontSize
        )
    }

    static func font(size: CGFloat) -> NSFont {
        .systemFont(ofSize: size, weight: .semibold)
    }

    static func textSize(_ text: String, fontSize: CGFloat) -> CGSize {
        let size = (text as NSString).size(withAttributes: [.font: font(size: fontSize)])
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }
}

/// The picture, the marks on it, and what is left of it after cropping and
/// resizing.
///
/// A value type, so undo is a stack of copies. Cropping and resizing are
/// recorded rather than applied: the original pixels are never touched until
/// the export, which is what makes both of them reversible.
struct ScreenshotDocument: Equatable, Sendable {

    /// Smallest crop worth keeping. A drag this small is a click, not a crop.
    static let minimumCrop: CGFloat = 8

    let pixelSize: CGSize
    var annotations: [Annotation] = []
    private(set) var crop: CGRect?
    private(set) var outputScale: CGFloat = 1

    init(pixelSize: CGSize) {
        self.pixelSize = pixelSize
    }

    var bounds: CGRect {
        CGRect(origin: .zero, size: pixelSize)
    }

    /// The region that survives into the export.
    var cropRect: CGRect {
        crop ?? bounds
    }

    /// Pixel dimensions of the exported image.
    var outputSize: CGSize {
        CGSize(
            width: max(1, (cropRect.width * outputScale).rounded()),
            height: max(1, (cropRect.height * outputScale).rounded())
        )
    }

    var isCropped: Bool { crop != nil }
    var isResized: Bool { outputScale != 1 }

    /// Keeps the part of `rect` that lies on the picture. A sliver is treated as
    /// "no crop" rather than producing an image that is a few pixels wide.
    mutating func setCrop(_ rect: CGRect) {
        let clamped = rect.standardized.intersection(bounds)
        guard !clamped.isNull,
              clamped.width >= Self.minimumCrop,
              clamped.height >= Self.minimumCrop
        else {
            crop = nil
            return
        }
        crop = clamped == bounds ? nil : clamped
    }

    mutating func resetCrop() {
        crop = nil
    }

    /// `1` is the cropped size; `0.5` halves both dimensions.
    mutating func setOutputScale(_ scale: CGFloat) {
        guard scale.isFinite, scale > 0 else { return }
        // Never enlarge past 4× — a typo of an extra digit should not ask for a
        // bitmap that cannot be allocated.
        outputScale = min(scale, 4)
    }

    /// Resizes to a width in pixels, keeping the aspect ratio.
    mutating func setOutputWidth(_ width: CGFloat) {
        guard cropRect.width > 0 else { return }
        setOutputScale(width / cropRect.width)
    }

    /// Resizes to a height in pixels, keeping the aspect ratio.
    mutating func setOutputHeight(_ height: CGFloat) {
        guard cropRect.height > 0 else { return }
        setOutputScale(height / cropRect.height)
    }

    /// Topmost annotation under a point in image space.
    func annotation(at point: CGPoint, tolerance: CGFloat = 0) -> Annotation? {
        annotations.last { $0.rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
    }
}
