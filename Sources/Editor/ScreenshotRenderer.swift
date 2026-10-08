import AppKit
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Draws a ``ScreenshotDocument``.
///
/// One drawing routine serves both the live editor and the export, on purpose:
/// two implementations of "draw an ellipse" drift apart by a pixel and a join
/// style, and then the picture that lands on the clipboard is not the one the
/// user was looking at.
///
/// Every function here draws into a context whose origin is the *top-left* and
/// whose unit is one image pixel. An `NSView` with `isFlipped` provides that
/// already; the export builds it.
enum ScreenshotRenderer {

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Export

    /// The finished picture: cropped, annotated, resized.
    static func render(base: CGImage, document: ScreenshotDocument) -> CGImage? {
        let output = document.outputSize
        let width = Int(output.width)
        let height = Int(output.height)

        let space = base.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high

        // Top-left origin, then image pixels, then the crop offset.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.scaleBy(x: output.width / document.cropRect.width, y: output.height / document.cropRect.height)
        context.translateBy(x: -document.cropRect.minX, y: -document.cropRect.minY)

        draw(base: base, document: document, in: context)
        return context.makeImage()
    }

    /// PNG bytes for `image`, keeping the source's pixel density.
    ///
    /// Without the density, a Retina capture comes back as a 72-dpi image of the
    /// same pixels and pastes at twice the size it was taken at.
    static func pngData(for image: CGImage, dpi: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }

        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// Pixels per inch recorded in an encoded image, or 72 when it says nothing.
    static func dpi(of data: Data) -> CGFloat {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let dpi = properties[kCGImagePropertyDPIWidth] as? CGFloat,
              dpi > 0
        else { return 72 }
        return dpi
    }

    // MARK: - Drawing

    /// The picture and every mark on it.
    static func draw(
        base: CGImage,
        document: ScreenshotDocument,
        in context: CGContext,
        pixelated: CGImage? = nil,
        skipping skipped: UUID? = nil
    ) {
        let bounds = document.bounds
        drawImage(base, in: bounds, context: context)

        let needsPixels = document.annotations.contains { $0.kind == .blur }
        let coarse = needsPixels ? (pixelated ?? self.pixelated(base)) : nil

        for annotation in document.annotations where annotation.id != skipped {
            draw(annotation, pixelated: coarse, in: context, canvas: bounds)
        }
    }

    static func draw(_ annotation: Annotation, pixelated: CGImage?, in context: CGContext, canvas: CGRect) {
        let rect = annotation.rect
        context.saveGState()
        defer { context.restoreGState() }

        let color = annotation.color.nsColor.cgColor

        switch annotation.kind {
        case .rectangle:
            context.setStrokeColor(color)
            context.setLineWidth(annotation.lineWidth)
            context.setLineJoin(.miter)
            context.stroke(rect.insetBy(dx: annotation.lineWidth / 2, dy: annotation.lineWidth / 2))

        case .ellipse:
            context.setStrokeColor(color)
            context.setLineWidth(annotation.lineWidth)
            context.strokeEllipse(in: rect.insetBy(dx: annotation.lineWidth / 2, dy: annotation.lineWidth / 2))

        case .highlight:
            // Multiply, so dark text underneath stays dark under a yellow marker
            // instead of being covered by a flat slab of it.
            context.setBlendMode(.multiply)
            context.setFillColor(annotation.color.nsColor.withAlphaComponent(0.55).cgColor)
            context.fill(rect)

        case .blur:
            guard let pixelated else { return }
            context.clip(to: rect.intersection(canvas))
            drawImage(pixelated, in: canvas, context: context)

        case .text:
            guard !annotation.text.isEmpty else { return }
            let graphics = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            (annotation.text as NSString).draw(
                at: rect.origin,
                withAttributes: [
                    .font: Annotation.font(size: annotation.fontSize),
                    .foregroundColor: annotation.color.nsColor,
                ]
            )
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// Draws a `CGImage` the right way up in a top-left-origin context.
    /// `CGContext.draw` assumes a bottom-left origin and would mirror it.
    static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    // MARK: - Blur

    /// A coarsely pixelated copy of the whole picture, made once so a blur
    /// annotation is just a window onto it.
    static func pixelated(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let block = max(10, CGFloat(max(image.width, image.height)) / 90)

        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(block, forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: input.extent.midX, y: input.extent.midY), forKey: kCIInputCenterKey)

        guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        return ciContext.createCGImage(output, from: input.extent)
    }
}
