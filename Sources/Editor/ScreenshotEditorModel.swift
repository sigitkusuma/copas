import AppKit
import CoreGraphics
import Observation

enum EditorTool: CaseIterable, Sendable {
    case select
    case rectangle
    case ellipse
    case text
    case highlight
    case blur
    case crop

    var title: String {
        switch self {
        case .select: "Select"
        case .rectangle: "Rectangle"
        case .ellipse: "Circle"
        case .text: "Text"
        case .highlight: "Highlight"
        case .blur: "Blur"
        case .crop: "Crop"
        }
    }

    var help: String {
        switch self {
        case .select: "Select and move marks. Delete removes the selected one."
        case .rectangle: "Draw a rectangle"
        case .ellipse: "Draw a circle or ellipse"
        case .text: "Click to place text"
        case .highlight: "Highlight an area"
        case .blur: "Pixelate an area to hide sensitive information"
        case .crop: "Drag the part of the picture to keep"
        }
    }

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .text: "textformat"
        case .highlight: "highlighter"
        case .blur: "squareshape.split.3x3"
        case .crop: "crop"
        }
    }

    /// The tools that make a new mark by dragging out a rectangle.
    var dragsOutAMark: Bool {
        switch self {
        case .rectangle, .ellipse, .highlight, .blur: true
        case .select, .text, .crop: false
        }
    }

    var annotationKind: AnnotationKind? {
        switch self {
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .highlight: .highlight
        case .blur: .blur
        case .text: .text
        case .select, .crop: nil
        }
    }
}

/// The state of one editing session.
///
/// Sizes the user picks are in *points*, and are multiplied by the picture's
/// pixel density when a mark is made. A 4-point outline means the same on a
/// Retina capture as on a standard one, instead of a hairline on the first.
@MainActor
@Observable
final class ScreenshotEditorModel {

    static let strokeChoices: [CGFloat] = [2, 4, 8]
    static let textChoices: [CGFloat] = [13, 18, 28]
    private static let undoDepth = 60

    @ObservationIgnored let base: CGImage
    @ObservationIgnored let pixelsPerPoint: CGFloat
    @ObservationIgnored let sourceDPI: CGFloat

    private(set) var document: ScreenshotDocument

    /// Selection only exists while the Select tool is in use. Left over, it would
    /// make the next colour click recolour the shape just drawn instead of
    /// choosing the colour of the one about to be.
    var tool: EditorTool = .rectangle {
        didSet {
            if tool != .select { selectedID = nil }
        }
    }
    private(set) var color: AnnotationColor = .red
    var strokePoints: CGFloat = 4
    var textPoints: CGFloat = 18
    private(set) var selectedID: UUID?

    private var undoStack: [ScreenshotDocument] = []
    private var redoStack: [ScreenshotDocument] = []

    /// Built the first time a blur is drawn. Pixelating a large capture is not
    /// free, and most edits never use it.
    @ObservationIgnored private(set) lazy var pixelated: CGImage? = ScreenshotRenderer.pixelated(base)

    init(base: CGImage, sourceDPI: CGFloat) {
        self.base = base
        self.sourceDPI = sourceDPI
        self.pixelsPerPoint = max(1, sourceDPI / 72)
        self.document = ScreenshotDocument(pixelSize: CGSize(width: base.width, height: base.height))
    }

    // MARK: - Undo

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Records the document as it is now, so the change about to be made can be
    /// undone as one step. A drag is one step, not one per mouse event.
    func beginChange() {
        undoStack.append(document)
        if undoStack.count > Self.undoDepth { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
        reconcileSelection()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        reconcileSelection()
    }

    private func reconcileSelection() {
        if let selectedID, !document.annotations.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
    }

    // MARK: - Marks

    var selectedAnnotation: Annotation? {
        document.annotations.first { $0.id == selectedID }
    }

    func select(_ id: UUID?) {
        selectedID = id
    }

    /// A new mark between two corners, in the current colour and weight.
    func makeAnnotation(_ kind: AnnotationKind, from start: CGPoint, to end: CGPoint) -> Annotation {
        Annotation(
            kind: kind,
            rect: CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y),
            color: kind == .highlight && color == .black ? .yellow : color,
            lineWidth: strokePoints * pixelsPerPoint
        )
    }

    func makeLabel(_ text: String, at origin: CGPoint) -> Annotation {
        Annotation.label(text, at: origin, color: color, fontSize: textPoints * pixelsPerPoint)
    }

    func add(_ annotation: Annotation) {
        beginChange()
        document.annotations.append(annotation)
    }

    /// Moves a mark. Call ``beginChange()`` once before a drag, not per step.
    func move(_ id: UUID, by delta: CGSize) {
        guard let index = document.annotations.firstIndex(where: { $0.id == id }) else { return }
        document.annotations[index].rect = document.annotations[index].rect.offsetBy(dx: delta.width, dy: delta.height)
    }

    func deleteSelected() {
        guard let selectedID, document.annotations.contains(where: { $0.id == selectedID }) else { return }
        beginChange()
        document.annotations.removeAll { $0.id == selectedID }
        self.selectedID = nil
    }

    /// Chooses the colour for new marks, and recolours the selected one.
    func choose(_ color: AnnotationColor) {
        self.color = color
        guard let selectedID,
              let index = document.annotations.firstIndex(where: { $0.id == selectedID }),
              document.annotations[index].color != color,
              document.annotations[index].kind != .blur
        else { return }
        beginChange()
        document.annotations[index].color = color
    }

    // MARK: - Crop and resize

    func setCrop(_ rect: CGRect) {
        let before = document
        var after = document
        after.setCrop(rect)
        guard after != before else { return }
        beginChange()
        document = after
    }

    func resetCrop() {
        guard document.isCropped else { return }
        beginChange()
        document.resetCrop()
    }

    func setOutputScale(_ scale: CGFloat) {
        var after = document
        after.setOutputScale(scale)
        guard after != document else { return }
        beginChange()
        document = after
    }

    func setOutputWidth(_ width: CGFloat) {
        var after = document
        after.setOutputWidth(width)
        guard after != document else { return }
        beginChange()
        document = after
    }

    func setOutputHeight(_ height: CGFloat) {
        var after = document
        after.setOutputHeight(height)
        guard after != document else { return }
        beginChange()
        document = after
    }

    // MARK: - Export

    func exportPNG() -> Data? {
        guard let image = ScreenshotRenderer.render(base: base, document: document) else { return nil }
        return ScreenshotRenderer.pngData(for: image, dpi: sourceDPI)
    }
}
