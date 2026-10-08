import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import Copas

struct ScreenshotDocumentTests {

    static let size = CGSize(width: 200, height: 100)

    @Test func aFreshDocumentExportsAtItsOwnSize() {
        let document = ScreenshotDocument(pixelSize: Self.size)
        #expect(document.cropRect == document.bounds)
        #expect(document.outputSize == Self.size)
        #expect(!document.isCropped)
        #expect(!document.isResized)
    }

    @Test func aCropIsClampedToThePicture() {
        var document = ScreenshotDocument(pixelSize: Self.size)
        document.setCrop(CGRect(x: -50, y: 20, width: 150, height: 500))
        #expect(document.cropRect == CGRect(x: 0, y: 20, width: 100, height: 80))
    }

    /// A drag can end up inverted, and the corner the user started from is not
    /// the origin of the rectangle.
    @Test func aDraggedBackwardsCropIsStandardised() {
        var document = ScreenshotDocument(pixelSize: Self.size)
        document.setCrop(CGRect(x: 100, y: 80, width: -60, height: -50))
        #expect(document.cropRect == CGRect(x: 40, y: 30, width: 60, height: 50))
    }

    @Test func aSliverIsNotACrop() {
        var document = ScreenshotDocument(pixelSize: Self.size)
        document.setCrop(CGRect(x: 10, y: 10, width: 60, height: 50))
        document.setCrop(CGRect(x: 10, y: 10, width: 3, height: 50))
        #expect(!document.isCropped, "a click is not a crop, and it clears the previous one")
    }

    @Test func cropToTheWholePictureIsNoCrop() {
        var document = ScreenshotDocument(pixelSize: Self.size)
        document.setCrop(CGRect(x: 0, y: 0, width: 200, height: 100))
        #expect(!document.isCropped)
    }

    @Test func resizingKeepsTheAspectRatioOfTheCrop() {
        var document = ScreenshotDocument(pixelSize: Self.size)
        document.setCrop(CGRect(x: 0, y: 0, width: 100, height: 50))
        document.setOutputWidth(50)
        #expect(document.outputSize == CGSize(width: 50, height: 25))

        document.setOutputHeight(100)
        #expect(document.outputSize == CGSize(width: 200, height: 100))
    }

    @Test func nonsenseScalesAreIgnoredAndHugeOnesCapped() {
        var document = ScreenshotDocument(pixelSize: Self.size)
        document.setOutputScale(0)
        document.setOutputScale(-2)
        document.setOutputScale(.nan)
        #expect(document.outputSize == Self.size)

        document.setOutputScale(500)
        #expect(document.outputSize == CGSize(width: 800, height: 400))
    }

    @Test func theTopmostAnnotationWinsAHitTest() {
        var document = ScreenshotDocument(pixelSize: Self.size)
        let below = Annotation(kind: .rectangle, rect: CGRect(x: 0, y: 0, width: 100, height: 100))
        let above = Annotation(kind: .ellipse, rect: CGRect(x: 40, y: 40, width: 100, height: 50))
        document.annotations = [below, above]

        #expect(document.annotation(at: CGPoint(x: 50, y: 50))?.id == above.id)
        #expect(document.annotation(at: CGPoint(x: 10, y: 10))?.id == below.id)
        #expect(document.annotation(at: CGPoint(x: 190, y: 5)) == nil)
    }
}

struct ScreenshotRendererTests {

    /// A picture of one flat colour, with a different colour in its top-left
    /// corner so a mirrored render cannot pass by accident.
    static func picture(width: Int = 100, height: Int = 80) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // CGContext's origin is bottom-left, so the *top-left* corner is high y.
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: height - 10, width: 10, height: 10))
        return context.makeImage()!
    }

    /// RGB of the pixel at `(x, y)` counted from the top-left.
    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Shift so the wanted pixel lands on the single one the context holds.
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    static func isWhite(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.r > 250 && p.g > 250 && p.b > 250 }
    static func isBlue(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.b > 250 && p.r < 5 && p.g < 5 }
    static func isRed(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.r > 200 && p.g < 80 && p.b < 80 }

    @Test func anUntouchedDocumentRendersTheOriginalTheRightWayUp() throws {
        let base = Self.picture()
        let image = try #require(ScreenshotRenderer.render(base: base, document: ScreenshotDocument(pixelSize: CGSize(width: 100, height: 80))))

        #expect(image.width == 100 && image.height == 80)
        #expect(Self.isBlue(Self.pixel(image, 2, 2)), "top-left marker stays top-left")
        #expect(Self.isWhite(Self.pixel(image, 90, 70)))
    }

    @Test func aRectangleIsDrawnWhereItWasPlaced() throws {
        let base = Self.picture()
        var document = ScreenshotDocument(pixelSize: CGSize(width: 100, height: 80))
        document.annotations = [
            Annotation(kind: .rectangle, rect: CGRect(x: 30, y: 20, width: 40, height: 30), color: .red, lineWidth: 4),
        ]
        let image = try #require(ScreenshotRenderer.render(base: base, document: document))

        #expect(Self.isRed(Self.pixel(image, 31, 35)), "left edge")
        #expect(Self.isRed(Self.pixel(image, 50, 21)), "top edge")
        #expect(Self.isWhite(Self.pixel(image, 50, 35)), "an outline, not a fill")
        #expect(Self.isWhite(Self.pixel(image, 10, 70)))
    }

    @Test func anEllipseTouchesItsEdgesButNotItsCorners() throws {
        let base = Self.picture()
        var document = ScreenshotDocument(pixelSize: CGSize(width: 100, height: 80))
        document.annotations = [
            Annotation(kind: .ellipse, rect: CGRect(x: 20, y: 10, width: 60, height: 60), color: .red, lineWidth: 4),
        ]
        let image = try #require(ScreenshotRenderer.render(base: base, document: document))

        #expect(Self.isRed(Self.pixel(image, 50, 11)), "top of the circle")
        #expect(Self.isRed(Self.pixel(image, 21, 40)), "left of the circle")
        #expect(Self.isWhite(Self.pixel(image, 22, 12)), "the bounding box corner is outside it")
    }

    @Test func aHighlightTintsWithoutHidingWhatIsUnderneath() throws {
        let base = Self.picture()
        var document = ScreenshotDocument(pixelSize: CGSize(width: 100, height: 80))
        document.annotations = [
            // Covers the blue corner marker and some white.
            Annotation(kind: .highlight, rect: CGRect(x: 0, y: 0, width: 30, height: 30), color: .yellow),
        ]
        let image = try #require(ScreenshotRenderer.render(base: base, document: document))

        let onWhite = Self.pixel(image, 20, 20)
        #expect(onWhite.r > 200 && onWhite.g > 200 && onWhite.b < 150, "yellow over white")
        let onBlue = Self.pixel(image, 2, 2)
        #expect(onBlue.b < 50 || onBlue.r < 50, "the blue underneath still shows through, darker")
        #expect(!Self.isWhite(onBlue))
    }

    @Test func blurChangesItsOwnAreaAndNothingElse() throws {
        // A hard vertical stripe, which pixelation must smear.
        let context = CGContext(
            data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        for x in stride(from: 0, to: 200, by: 4) {
            context.fill(CGRect(x: x, y: 0, width: 2, height: 200))
        }
        let base = context.makeImage()!

        var document = ScreenshotDocument(pixelSize: CGSize(width: 200, height: 200))
        document.annotations = [Annotation(kind: .blur, rect: CGRect(x: 0, y: 0, width: 100, height: 200))]
        let image = try #require(ScreenshotRenderer.render(base: base, document: document))

        // Inside: stripes of 2px are gone, so neighbouring pixels agree.
        let a = Self.pixel(image, 40, 100)
        let b = Self.pixel(image, 41, 100)
        #expect(abs(a.r - b.r) < 40, "the stripes are smeared")
        // Outside: the original stripes are intact.
        let c = Self.pixel(image, 160, 100)
        let d = Self.pixel(image, 162, 100)
        #expect(abs(c.r - d.r) > 200, "untouched")
    }

    @Test func textLeavesInkWhereItIsPlaced() throws {
        let base = Self.picture(width: 200, height: 80)
        var document = ScreenshotDocument(pixelSize: CGSize(width: 200, height: 80))
        document.annotations = [
            Annotation.label("MMMM", at: CGPoint(x: 30, y: 20), color: .black, fontSize: 28),
        ]
        let image = try #require(ScreenshotRenderer.render(base: base, document: document))

        let rect = document.annotations[0].rect
        var dark = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) where Self.pixel(image, x, y).r < 100 { dark += 1 }
        }
        #expect(dark > 50, "glyphs were drawn inside the label's own rectangle")
        #expect(Self.isWhite(Self.pixel(image, 150, 70)), "and not elsewhere")
    }

    @Test func cropThenResizeProducesTheRequestedSizeFromTheRightRegion() throws {
        let base = Self.picture()
        var document = ScreenshotDocument(pixelSize: CGSize(width: 100, height: 80))
        document.setCrop(CGRect(x: 0, y: 0, width: 40, height: 40))
        document.setOutputScale(0.5)
        let image = try #require(ScreenshotRenderer.render(base: base, document: document))

        #expect(image.width == 20 && image.height == 20)
        #expect(Self.isBlue(Self.pixel(image, 1, 1)), "the marker was inside the crop")
    }

    @Test func aCropMovesAnnotationsWithThePicture() throws {
        let base = Self.picture()
        var document = ScreenshotDocument(pixelSize: CGSize(width: 100, height: 80))
        document.annotations = [
            Annotation(kind: .rectangle, rect: CGRect(x: 50, y: 40, width: 30, height: 30), color: .red, lineWidth: 4),
        ]
        document.setCrop(CGRect(x: 40, y: 30, width: 60, height: 50))
        let image = try #require(ScreenshotRenderer.render(base: base, document: document))

        // The rectangle's left edge, at x=50 in the picture, is x=10 in the crop.
        #expect(Self.isRed(Self.pixel(image, 11, 20)))
    }

    @Test func pngKeepsThePixelDensity() throws {
        let png = try #require(ScreenshotRenderer.pngData(for: Self.picture(), dpi: 144))
        #expect(ScreenshotRenderer.dpi(of: png) == 144)
        #expect(ScreenshotRenderer.dpi(of: Data("not an image".utf8)) == 72)
    }
}

@MainActor
struct ScreenshotEditorModelTests {

    static func model() -> ScreenshotEditorModel {
        ScreenshotEditorModel(base: ScreenshotRendererTests.picture(), sourceDPI: 144)
    }

    @Test func sizesAreChosenInPointsAndScaledToThePictureDensity() {
        let model = Self.model()
        model.strokePoints = 4
        let mark = model.makeAnnotation(.rectangle, from: .zero, to: CGPoint(x: 10, y: 10))
        #expect(mark.lineWidth == 8, "4 pt on a 2x capture is 8 px")
    }

    @Test func undoAndRedoWalkThroughEdits() {
        let model = Self.model()
        model.add(model.makeAnnotation(.rectangle, from: .zero, to: CGPoint(x: 20, y: 20)))
        model.add(model.makeAnnotation(.ellipse, from: .zero, to: CGPoint(x: 30, y: 30)))
        #expect(model.document.annotations.count == 2)

        model.undo()
        #expect(model.document.annotations.count == 1)
        model.undo()
        #expect(model.document.annotations.isEmpty)
        #expect(!model.canUndo)

        model.redo()
        #expect(model.document.annotations.count == 1)
        model.add(model.makeAnnotation(.blur, from: .zero, to: CGPoint(x: 5, y: 5)))
        #expect(!model.canRedo, "a new edit ends the redo branch")
    }

    @Test func cropAndResizeAreUndoable() {
        let model = Self.model()
        model.setCrop(CGRect(x: 0, y: 0, width: 50, height: 40))
        model.setOutputScale(0.5)
        #expect(model.document.outputSize == CGSize(width: 25, height: 20))

        model.undo()
        #expect(model.document.outputSize == CGSize(width: 50, height: 40))
        model.undo()
        #expect(!model.document.isCropped)
    }

    /// Setting what is already set is not a step in the history.
    @Test func aNoOpDoesNotCluttertheUndoStack() {
        let model = Self.model()
        model.setOutputScale(1)
        model.setCrop(CGRect(x: 0, y: 0, width: 3, height: 3))
        model.resetCrop()
        #expect(!model.canUndo)
    }

    @Test func aNewShapeDoesNotStealTheNextColour() {
        let model = Self.model()
        model.choose(.red)
        model.add(model.makeAnnotation(.rectangle, from: .zero, to: CGPoint(x: 20, y: 20)))
        model.choose(.blue)
        #expect(model.document.annotations[0].color == .red, "the earlier shape is left alone")

        let next = model.makeAnnotation(.rectangle, from: .zero, to: CGPoint(x: 20, y: 20))
        #expect(next.color == .blue)
    }

    @Test func aColourClickRecoloursTheSelectedMark() {
        let model = Self.model()
        let mark = model.makeAnnotation(.rectangle, from: .zero, to: CGPoint(x: 20, y: 20))
        model.add(mark)
        model.tool = .select
        model.select(mark.id)
        model.choose(.green)
        #expect(model.document.annotations[0].color == .green)

        model.undo()
        #expect(model.document.annotations[0].color == .red)
    }

    @Test func leavingTheSelectToolDropsTheSelection() {
        let model = Self.model()
        let mark = model.makeAnnotation(.rectangle, from: .zero, to: CGPoint(x: 20, y: 20))
        model.add(mark)
        model.tool = .select
        model.select(mark.id)
        model.tool = .ellipse
        #expect(model.selectedID == nil)
    }

    @Test func deletingTheSelectedMarkIsUndoable() {
        let model = Self.model()
        let mark = model.makeAnnotation(.rectangle, from: .zero, to: CGPoint(x: 20, y: 20))
        model.add(mark)
        model.tool = .select
        model.select(mark.id)
        model.deleteSelected()
        #expect(model.document.annotations.isEmpty)
        model.undo()
        #expect(model.document.annotations.count == 1)
    }

    @Test func aHighlightNeverComesOutBlack() {
        let model = Self.model()
        model.choose(.black)
        let mark = model.makeAnnotation(.highlight, from: .zero, to: CGPoint(x: 20, y: 20))
        #expect(mark.color == .yellow, "a black marker would erase the text it highlights")
    }

    @Test func exportKeepsTheSourceDensity() throws {
        let model = Self.model()
        let png = try #require(model.exportPNG())
        #expect(ScreenshotRenderer.dpi(of: png) == 144)
    }
}

/// Drives the real canvas with synthesised mouse events, to pin the one thing
/// that is easy to get subtly wrong: where a drag on screen lands on the picture.
@MainActor
struct EditorCanvasTests {

    /// Windows are held for the process lifetime; a view's window is weak, and a
    /// test's canvas would otherwise lose it before the events arrive.
    static var retainedWindows: [NSWindow] = []

    /// A 600×360 px capture at 144 dpi shows at 300×180 pt, centred.
    static func canvas() -> (EditorCanvasView, ScreenshotEditorModel) {
        let model = ScreenshotEditorModel(
            base: ScreenshotRendererTests.picture(width: 600, height: 360),
            sourceDPI: 144
        )
        let canvas = EditorCanvasView(model: model)
        // A real window, never shown: without one, AppKit has no base
        // coordinate space to convert an event's location out of.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 376),
            styleMask: [.borderless], backing: .buffered, defer: true
        )
        window.contentView = canvas
        canvas.frame = NSRect(x: 0, y: 0, width: 700, height: 376)
        Self.retainedWindows.append(window)
        canvas.apply(document: model.document, tool: model.tool, selectedID: nil, color: model.color, textPoints: model.textPoints)
        return (canvas, model)
    }

    /// Image pixel → view point: half scale, picture centred in the 700×376 view.
    static func view(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: 200 + x * 0.5, y: 98 + y * 0.5)
    }

    static func event(_ type: NSEvent.EventType, _ point: CGPoint, in canvas: EditorCanvasView) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: canvas.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
    }

    static func drag(_ canvas: EditorCanvasView, _ model: ScreenshotEditorModel, tool: EditorTool, from a: CGPoint, to b: CGPoint) {
        model.tool = tool
        canvas.apply(document: model.document, tool: tool, selectedID: model.selectedID, color: model.color, textPoints: model.textPoints)
        canvas.mouseDown(with: event(.leftMouseDown, a, in: canvas))
        canvas.mouseDragged(with: event(.leftMouseDragged, b, in: canvas))
        canvas.mouseUp(with: event(.leftMouseUp, b, in: canvas))
        canvas.apply(document: model.document, tool: tool, selectedID: model.selectedID, color: model.color, textPoints: model.textPoints)
    }

    @Test func aDragBecomesAMarkAtTheSamePlaceOnThePicture() {
        let (canvas, model) = Self.canvas()
        Self.drag(canvas, model, tool: .rectangle, from: Self.view(20, 100), to: Self.view(150, 200))

        #expect(model.document.annotations.count == 1)
        #expect(model.document.annotations.first?.rect == CGRect(x: 20, y: 100, width: 130, height: 100))
    }

    @Test func aDragBackwardsStillMakesAProperRectangle() {
        let (canvas, model) = Self.canvas()
        Self.drag(canvas, model, tool: .ellipse, from: Self.view(150, 200), to: Self.view(20, 100))
        #expect(model.document.annotations.first?.rect == CGRect(x: 20, y: 100, width: 130, height: 100))
    }

    @Test func aDragThatLeavesThePictureIsKeptOnIt() {
        let (canvas, model) = Self.canvas()
        Self.drag(canvas, model, tool: .rectangle, from: Self.view(500, 300), to: CGPoint(x: 5_000, y: 5_000))
        #expect(model.document.annotations.first?.rect == CGRect(x: 500, y: 300, width: 100, height: 60))
    }

    @Test func aClickIsNotAShape() {
        let (canvas, model) = Self.canvas()
        Self.drag(canvas, model, tool: .rectangle, from: Self.view(100, 100), to: Self.view(101, 101))
        #expect(model.document.annotations.isEmpty)
    }

    @Test func aWholeDragIsOneUndoStep() {
        let (canvas, model) = Self.canvas()
        Self.drag(canvas, model, tool: .rectangle, from: Self.view(20, 100), to: Self.view(150, 200))
        model.undo()
        #expect(model.document.annotations.isEmpty)
        #expect(!model.canUndo)
    }

    @Test func theCropToolSetsTheCropInPictureCoordinates() {
        let (canvas, model) = Self.canvas()
        Self.drag(canvas, model, tool: .crop, from: Self.view(10, 10), to: Self.view(510, 330))
        #expect(model.document.cropRect == CGRect(x: 10, y: 10, width: 500, height: 320))
        #expect(model.document.annotations.isEmpty, "cropping is not a mark")
    }

    @Test func theSelectToolMovesAMarkByTheDragDistance() {
        let (canvas, model) = Self.canvas()
        Self.drag(canvas, model, tool: .rectangle, from: Self.view(20, 100), to: Self.view(150, 200))
        Self.drag(canvas, model, tool: .select, from: Self.view(80, 150), to: Self.view(130, 170))

        // From picture (80, 150) to (130, 170): 50 px right, 20 px down.
        #expect(model.document.annotations.first?.rect == CGRect(x: 70, y: 120, width: 130, height: 100))
        model.undo()
        #expect(model.document.annotations.first?.rect == CGRect(x: 20, y: 100, width: 130, height: 100), "the move was one step")
    }
}
