import CoreGraphics
import CoreImage
import Foundation
import Vision

/// Cleans up a photographed page before OCR ever sees it.
///
/// A phone photo of a handwritten note rarely arrives flat and evenly lit: the
/// page sits at an angle, a shadow crosses part of it, and low contrast
/// between ink and paper is common. Neither Live Text nor Vision reads that
/// well no matter how they're configured — the fix has to happen to the
/// pixels first.
enum ImagePreprocessor {

    static func prepare(_ image: CGImage) -> CGImage {
        let deskewed = deskewed(image) ?? image
        return contrastBoosted(deskewed) ?? deskewed
    }

    // MARK: - Deskew

    /// Finds the page in the frame, if there plausibly is one, and warps it
    /// flat with `CIPerspectiveCorrection`.
    private static func deskewed(_ image: CGImage) -> CGImage? {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Log.app.error("document segmentation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        guard
            let observation = request.results?.first,
            shouldCorrectPerspective(
                topLeft: observation.topLeft,
                topRight: observation.topRight,
                bottomRight: observation.bottomRight,
                bottomLeft: observation.bottomLeft,
                confidence: observation.confidence
            )
        else { return nil }

        let ciImage = CIImage(cgImage: image)
        let extent = ciImage.extent
        func denormalized(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * extent.width, y: point.y * extent.height)
        }

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: denormalized(observation.topLeft)), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: denormalized(observation.topRight)), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: denormalized(observation.bottomRight)), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: denormalized(observation.bottomLeft)), forKey: "inputBottomLeft")

        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output, from: output.extent)
    }

    /// Whether a detected quadrilateral is worth warping the image over.
    ///
    /// Pure, so the thresholds can be tested without a real detector. Both
    /// gates are deliberately conservative: skipping a photo that could have
    /// used correction costs nothing, but "correcting" a screenshot against a
    /// spurious rectangle — a window edge, a panel — actively distorts text
    /// that was already readable. Requiring high confidence over most of the
    /// frame means only something that looks unmistakably like a held-up page
    /// qualifies; a warp against a full-frame, barely-skewed quad is
    /// otherwise close enough to the identity transform to be harmless.
    static func shouldCorrectPerspective(
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomRight: CGPoint,
        bottomLeft: CGPoint,
        confidence: Float,
        minimumConfidence: Float = 0.85,
        minimumCoverage: Double = 0.4
    ) -> Bool {
        guard confidence >= minimumConfidence else { return false }

        let coverage = normalizedArea(
            topLeft: topLeft,
            topRight: topRight,
            bottomRight: bottomRight,
            bottomLeft: bottomLeft
        )
        return coverage >= minimumCoverage
    }

    /// The area of a quadrilateral in normalized (0...1) image coordinates,
    /// via the shoelace formula.
    private static func normalizedArea(
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomRight: CGPoint,
        bottomLeft: CGPoint
    ) -> Double {
        let points = [topLeft, topRight, bottomRight, bottomLeft]
        var sum = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            sum += current.x * next.y - next.x * current.y
        }
        return abs(sum) / 2
    }

    // MARK: - Contrast

    /// A modest, fixed contrast lift. Ink-on-paper photos are usually
    /// low-contrast next to a digital screenshot; this narrows that gap
    /// without pushing hard enough to clip a screenshot's own colors.
    private static func contrastBoosted(_ image: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(1.15, forKey: kCIInputContrastKey)
        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output, from: output.extent)
    }

    private static let context = CIContext()
}
