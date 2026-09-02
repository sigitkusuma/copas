import Foundation
import Testing

@testable import Copas

struct BoardGeometryTests {

    static let size = CGSize(width: 760, height: 580)

    /// Centred horizontally, and hanging from the top of the free space — where
    /// the status item that opens it already is, and where the eye is already
    /// looking after a keystroke.
    @Test func theBoardIsCentredAndWeightedToTheTop() {
        let visible = CGRect(x: 0, y: 70, width: 1_512, height: 900)
        let frame = BoardGeometry.frame(in: visible, size: Self.size, inset: 40)

        #expect(frame.width == 760)
        #expect(frame.height == 580)
        #expect(frame.midX == visible.midX)
        #expect(frame.maxY == visible.maxY - 40, "a gap under the menu bar, not flush with it")
    }

    /// The other edge is a setting, so it has to place the panel just as well.
    @Test func theBottomEdgeSitsAboveTheDock() {
        let visible = CGRect(x: 0, y: 70, width: 1_512, height: 900)
        let frame = BoardGeometry.frame(in: visible, edge: .bottom, size: Self.size, inset: 40)

        #expect(frame.minY == visible.minY + 40)
        #expect(frame.midX == visible.midX)
    }

    /// A panel wider or taller than the screen would hang off it, and on a
    /// laptop beside a projector that is not a hypothetical.
    @Test func aSmallScreenGetsASmallerBoard() {
        let visible = CGRect(x: 0, y: 0, width: 640, height: 500)
        let frame = BoardGeometry.frame(in: visible, size: Self.size, inset: 40)

        #expect(frame.width == 640)
        #expect(frame.height == 500)
        #expect(frame.minX == 0)
        #expect(frame.minY == 0, "the gap collapses rather than pushing the panel off the top")
    }

    /// The inset has to give way before the panel does: a screen with less free
    /// space than the gap asks for still shows the whole panel.
    @Test func theGapCollapsesBeforeTheBoardDoes() {
        let visible = CGRect(x: 0, y: 0, width: 1_000, height: 600)
        let frame = BoardGeometry.frame(in: visible, size: Self.size, inset: 40)

        #expect(frame.height == 580, "the panel keeps its size")
        #expect(frame.maxY == visible.maxY - 20, "and the 20 points of slack become the gap")
        #expect(frame.minY == visible.minY, "which leaves it resting on the bottom edge")
    }

    /// A second display sits at a non-zero origin, and a board that ignored that
    /// would open on the wrong screen — or half off the edge of one.
    @Test func aScreenToTheRightKeepsItsOrigin() {
        let visible = CGRect(x: 1_512, y: 0, width: 1_920, height: 1_080)
        let frame = BoardGeometry.frame(in: visible, size: Self.size, inset: 40)

        #expect(frame.midX == visible.midX)
        #expect(frame.minX >= visible.minX)
        #expect(frame.maxX <= visible.maxX)
        #expect(frame.maxY == visible.maxY - 40)
    }

    @Test func theBoardFollowsThePointer() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1_512, height: 982),
            CGRect(x: 1_512, y: 0, width: 1_920, height: 1_080),
        ]
        #expect(BoardGeometry.screenIndex(containing: CGPoint(x: 200, y: 400), among: screens) == 0)
        #expect(BoardGeometry.screenIndex(containing: CGPoint(x: 2_000, y: 400), among: screens) == 1)
    }

    @Test func aPointerInNoScreenAtAllFallsBack() {
        let screens = [CGRect(x: 0, y: 0, width: 100, height: 100)]
        #expect(BoardGeometry.screenIndex(containing: CGPoint(x: 500, y: 500), among: screens) == nil)
    }
}
