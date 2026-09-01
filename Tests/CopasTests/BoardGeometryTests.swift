import Foundation
import Testing

@testable import Copas

struct BoardGeometryTests {

    /// Measured against the *visible* frame, so the board rests on the Dock
    /// rather than hiding underneath it.
    @Test func theBoardSitsOnTheBottomEdgeAndSpansTheWidth() {
        let visible = CGRect(x: 0, y: 70, width: 1_512, height: 900)
        let frame = BoardGeometry.frame(in: visible, height: 420)

        #expect(frame == CGRect(x: 0, y: 70, width: 1_512, height: 420))
    }

    @Test func aShortScreenGetsAShorterBoard() {
        let visible = CGRect(x: 0, y: 0, width: 1_024, height: 300)
        #expect(BoardGeometry.frame(in: visible, height: 420).height == 300)
    }

    /// A second display sits at a non-zero origin, and a board that ignored that
    /// would open on the wrong screen — or half off the edge of one.
    @Test func aScreenToTheRightKeepsItsOrigin() {
        let visible = CGRect(x: 1_512, y: 0, width: 1_920, height: 1_080)
        let frame = BoardGeometry.frame(in: visible, height: 420)

        #expect(frame.minX == 1_512)
        #expect(frame.minY == 0)
        #expect(frame.width == 1_920)
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
