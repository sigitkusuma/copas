import Foundation
import Testing

@testable import Copas

struct BoardGeometryTests {

    /// Hangs from the menu bar, which is where the status item that opens it
    /// already is. Measured against the *visible* frame, so it clears the menu
    /// bar rather than hiding underneath it.
    @Test func theBoardHangsFromTheTopEdgeAndSpansTheWidth() {
        let visible = CGRect(x: 0, y: 70, width: 1_512, height: 900)
        let frame = BoardGeometry.frame(in: visible, height: 420)

        #expect(frame == CGRect(x: 0, y: 550, width: 1_512, height: 420))
        #expect(frame.maxY == visible.maxY, "flush with the bottom of the menu bar")
    }

    /// The other edge still works, because it is a setting waiting to be offered.
    @Test func theBottomEdgeRestsOnTheDock() {
        let visible = CGRect(x: 0, y: 70, width: 1_512, height: 900)
        let frame = BoardGeometry.frame(in: visible, edge: .bottom, height: 420)

        #expect(frame == CGRect(x: 0, y: 70, width: 1_512, height: 420))
    }

    @Test func aShortScreenGetsAShorterBoard() {
        let visible = CGRect(x: 0, y: 0, width: 1_024, height: 300)
        let frame = BoardGeometry.frame(in: visible, height: 420)

        #expect(frame.height == 300)
        #expect(frame.minY == 0, "a board taller than the screen must not hang off the top")
    }

    /// A second display sits at a non-zero origin, and a board that ignored that
    /// would open on the wrong screen — or half off the edge of one.
    @Test func aScreenToTheRightKeepsItsOrigin() {
        let visible = CGRect(x: 1_512, y: 0, width: 1_920, height: 1_080)
        let frame = BoardGeometry.frame(in: visible, height: 420)

        #expect(frame.minX == 1_512)
        #expect(frame.maxY == 1_080)
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
