import AppKit
import SwiftUI

/// The picture and everything drawn on it, and the mouse and keyboard handling
/// that draws it.
///
/// AppKit rather than a SwiftUI `Canvas`: a flipped `NSView` gives a top-left
/// origin that matches the image-space coordinates of ``Annotation`` exactly,
/// and hands over `mouseDown`, `mouseDragged` and `keyDown` without a gesture
/// layer between them and the point being hit.
struct EditorCanvas: NSViewRepresentable {

    let model: ScreenshotEditorModel
    // Passed as plain values, read by the parent's body, so SwiftUI knows to
    // call `updateNSView` when any of them change.
    let document: ScreenshotDocument
    let tool: EditorTool
    let selectedID: UUID?
    let color: AnnotationColor
    let textPoints: CGFloat

    func makeNSView(context: Context) -> EditorCanvasView {
        let view = EditorCanvasView(model: model)
        view.apply(document: document, tool: tool, selectedID: selectedID, color: color, textPoints: textPoints)
        return view
    }

    func updateNSView(_ view: EditorCanvasView, context: Context) {
        view.apply(document: document, tool: tool, selectedID: selectedID, color: color, textPoints: textPoints)
    }
}

final class EditorCanvasView: NSView, NSTextFieldDelegate {

    private let model: ScreenshotEditorModel

    private var document: ScreenshotDocument
    private var tool: EditorTool = .rectangle
    private var selectedID: UUID?
    private var color: AnnotationColor = .red
    private var textPoints: CGFloat = 18

    /// What is being dragged out right now. Held here rather than in the model
    /// so a drag is one undo step, made on release, and so nothing is
    /// published to SwiftUI sixty times a second.
    private var draft: Annotation?
    private var cropDraft: CGRect?

    private enum Drag {
        case none
        case draw(start: CGPoint)
        case crop(start: CGPoint)
        case move(id: UUID, last: CGPoint)
    }
    private var drag: Drag = .none

    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero

    private let padding: CGFloat = 24

    @MainActor
    init(model: ScreenshotEditorModel) {
        self.model = model
        self.document = model.document
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    @MainActor
    func apply(document: ScreenshotDocument, tool: EditorTool, selectedID: UUID?, color: AnnotationColor, textPoints: CGFloat) {
        let toolChanged = self.tool != tool
        self.document = document
        self.tool = tool
        self.selectedID = selectedID
        self.color = color
        self.textPoints = textPoints
        if toolChanged {
            commitText()
            draft = nil
            cropDraft = nil
            window?.invalidateCursorRects(for: self)
        }
        needsDisplay = true
    }

    // MARK: - Geometry

    /// View points per image pixel. Never above true size, so a small capture is
    /// not blown up into a blur.
    private var scale: CGFloat {
        let available = CGSize(width: max(1, bounds.width - padding * 2), height: max(1, bounds.height - padding * 2))
        let fit = min(available.width / document.pixelSize.width, available.height / document.pixelSize.height)
        return min(fit, 1 / model.pixelsPerPoint)
    }

    private var origin: CGPoint {
        let s = scale
        return CGPoint(
            x: (bounds.width - document.pixelSize.width * s) / 2,
            y: (bounds.height - document.pixelSize.height * s) / 2
        )
    }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        let s = scale, o = origin
        let raw = CGPoint(x: (p.x - o.x) / s, y: (p.y - o.y) / s)
        return CGPoint(
            x: min(max(raw.x, 0), document.pixelSize.width),
            y: min(max(raw.y, 0), document.pixelSize.height)
        )
    }

    private func viewPoint(_ imagePoint: CGPoint) -> CGPoint {
        let s = scale, o = origin
        return CGPoint(x: o.x + imagePoint.x * s, y: o.y + imagePoint.y * s)
    }

    // MARK: - Drawing

    @MainActor
    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let s = scale, o = origin

        context.saveGState()
        context.translateBy(x: o.x, y: o.y)
        context.scaleBy(x: s, y: s)
        context.interpolationQuality = .high

        var shown = document
        if let draft { shown.annotations.append(draft) }

        let needsPixels = shown.annotations.contains { $0.kind == .blur }
        ScreenshotRenderer.draw(
            base: model.base,
            document: shown,
            in: context,
            pixelated: needsPixels ? model.pixelated : nil
        )

        drawSelection(in: context, scale: s)
        drawCrop(in: context, scale: s)

        context.restoreGState()
    }

    private func drawSelection(in context: CGContext, scale s: CGFloat) {
        guard tool != .crop,
              let selected = document.annotations.first(where: { $0.id == selectedID })
        else { return }

        context.saveGState()
        let rect = selected.rect.insetBy(dx: -3 / s, dy: -3 / s)
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(1.5 / s)
        context.setLineDash(phase: 0, lengths: [5 / s, 3 / s])
        context.stroke(rect)
        context.restoreGState()
    }

    private func drawCrop(in context: CGContext, scale s: CGFloat) {
        let active = cropDraft ?? (document.isCropped ? document.cropRect : nil)
        guard let active else { return }

        context.saveGState()
        // Everything outside the kept region, dimmed: the even-odd rule fills
        // the picture minus the crop in one path.
        context.addRect(document.bounds)
        context.addRect(active)
        context.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        context.fillPath(using: .evenOdd)

        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1.5 / s)
        context.stroke(active)
        context.restoreGState()
    }

    // MARK: - Mouse

    override func resetCursorRects() {
        let cursor: NSCursor = switch tool {
        case .select: .arrow
        case .text: .iBeam
        default: .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    @MainActor
    override func mouseDown(with event: NSEvent) {
        commitText()
        window?.makeFirstResponder(self)

        let point = imagePoint(event)
        switch tool {
        case .select:
            let hit = document.annotation(at: point, tolerance: 6 / scale)
            model.select(hit?.id)
            if let hit {
                model.beginChange()
                drag = .move(id: hit.id, last: point)
            }

        case .rectangle, .ellipse, .highlight, .blur:
            model.select(nil)
            drag = .draw(start: point)

        case .crop:
            drag = .crop(start: point)
            cropDraft = CGRect(origin: point, size: .zero)

        case .text:
            model.select(nil)
            beginText(at: point)
        }
    }

    @MainActor
    override func mouseDragged(with event: NSEvent) {
        let point = imagePoint(event)
        switch drag {
        case .none:
            break

        case .draw(let start):
            if let kind = tool.annotationKind {
                draft = model.makeAnnotation(kind, from: start, to: point)
            }

        case .crop(let start):
            cropDraft = CGRect(x: start.x, y: start.y, width: point.x - start.x, height: point.y - start.y).standardized

        case .move(let id, let last):
            model.move(id, by: CGSize(width: point.x - last.x, height: point.y - last.y))
            drag = .move(id: id, last: point)
        }
        needsDisplay = true
    }

    @MainActor
    override func mouseUp(with event: NSEvent) {
        defer {
            drag = .none
            draft = nil
            cropDraft = nil
            needsDisplay = true
        }

        switch drag {
        case .draw:
            // A click is not a rectangle.
            if let draft, draft.rect.width >= 4, draft.rect.height >= 4 {
                model.add(draft)
            }
        case .crop:
            if let cropDraft {
                model.setCrop(cropDraft)
            }
        case .move, .none:
            break
        }
    }

    // MARK: - Keyboard

    @MainActor
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117: // delete, forward delete
            model.deleteSelected()
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Text

    @MainActor
    private func beginText(at point: CGPoint) {
        commitText()

        let fontPoints = textPoints * model.pixelsPerPoint * scale
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Annotation.font(size: fontPoints)
        field.textColor = color.nsColor
        field.placeholderString = "Text"
        field.delegate = self
        field.target = self
        field.action = #selector(textFieldAction)
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true

        // The field's own cell insets the text a couple of points; shifting the
        // frame back keeps the glyphs where the exported text will be.
        let inset: CGFloat = 2
        let viewOrigin = viewPoint(point)
        let height = ceil(Annotation.textSize("Ag", fontSize: fontPoints).height) + 2
        field.frame = NSRect(x: viewOrigin.x - inset, y: viewOrigin.y - 1, width: 160, height: height)

        addSubview(field)
        textField = field
        textOrigin = point
        window?.makeFirstResponder(field)
    }

    @MainActor
    @objc private func textFieldAction() {
        commitText()
    }

    @MainActor
    private func commitText() {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        window?.makeFirstResponder(self)

        guard !text.isEmpty else { return }
        model.add(model.makeLabel(text, at: textOrigin))
    }

    @MainActor
    func controlTextDidChange(_ notification: Notification) {
        guard let field = textField else { return }
        let width = ceil(Annotation.textSize(field.stringValue + "  ", fontSize: field.font?.pointSize ?? 14).width)
        field.setFrameSize(NSSize(width: max(80, width + 8), height: field.frame.height))
    }

    @MainActor
    func controlTextDidEndEditing(_ notification: Notification) {
        // Clicking away commits, like Return does.
        commitText()
    }

    @MainActor
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        // Escape abandons the label, rather than closing the whole editor.
        textField?.removeFromSuperview()
        textField = nil
        window?.makeFirstResponder(self)
        return true
    }
}
