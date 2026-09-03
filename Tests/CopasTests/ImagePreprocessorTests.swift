import CoreGraphics
import Testing

@testable import Copas

struct ImagePreprocessorTests {

    /// Vision's coordinate space: normalised, origin bottom-left.
    private func quad(width: CGFloat, height: CGFloat) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
        (
            CGPoint(x: 0, y: height),
            CGPoint(x: width, y: height),
            CGPoint(x: width, y: 0),
            CGPoint(x: 0, y: 0)
        )
    }

    @Test func aConfidentFullFrameQuadIsWorthCorrecting() {
        let (topLeft, topRight, bottomRight, bottomLeft) = quad(width: 1, height: 1)
        #expect(ImagePreprocessor.shouldCorrectPerspective(
            topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft,
            confidence: 0.95
        ))
    }

    /// A UI screenshot can contain small rectangular chrome — a button, a
    /// panel — that a document detector might latch onto. It shouldn't be
    /// mistaken for a held-up page just because the detector is confident.
    @Test func aSmallConfidentQuadIsNotWorthCorrecting() {
        let (topLeft, topRight, bottomRight, bottomLeft) = quad(width: 0.2, height: 0.2)
        #expect(!ImagePreprocessor.shouldCorrectPerspective(
            topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft,
            confidence: 0.99
        ))
    }

    @Test func aLargeButUnconfidentQuadIsNotWorthCorrecting() {
        let (topLeft, topRight, bottomRight, bottomLeft) = quad(width: 1, height: 1)
        #expect(!ImagePreprocessor.shouldCorrectPerspective(
            topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft,
            confidence: 0.5
        ))
    }

    @Test func aSkewedPageFillingMostOfTheFrameIsWorthCorrecting() {
        // A page held up at an angle: corners pulled in unevenly rather than
        // forming a clean axis-aligned rectangle.
        #expect(ImagePreprocessor.shouldCorrectPerspective(
            topLeft: CGPoint(x: 0.05, y: 0.95),
            topRight: CGPoint(x: 0.9, y: 0.85),
            bottomRight: CGPoint(x: 0.95, y: 0.1),
            bottomLeft: CGPoint(x: 0.1, y: 0.05),
            confidence: 0.9
        ))
    }
}
