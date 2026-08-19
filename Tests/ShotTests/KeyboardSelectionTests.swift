import AppKit
import Testing
@testable import Shot

@Suite("Keyboard selection")
struct KeyboardSelectionTests {
    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

    private func selection(
        cursor: CGPoint = CGPoint(x: 200, y: 150)
    ) -> KeyboardSelection {
        KeyboardSelection(bounds: bounds, cursor: cursor)
    }

    private func key(_ characters: String, shift: Bool = false) -> SelectionKey? {
        SelectionKey.resolve(characters: characters, modifiers: shift ? .shift : [])
    }

    @Test
    func motionKeysMatchTheUnflippedViewCoordinates() {
        let step = SelectionKey.step
        #expect(key("h") == .move(dx: -step, dy: 0))
        #expect(key("l") == .move(dx: step, dy: 0))
        // The selection view is not flipped, so j moves toward smaller y.
        #expect(key("j") == .move(dx: 0, dy: -step))
        #expect(key("k") == .move(dx: 0, dy: step))
    }

    @Test
    func shiftedMotionKeysDropToPixelPrecision() {
        let precise = SelectionKey.preciseStep
        #expect(precise < SelectionKey.step)
        #expect(key("H", shift: true) == .move(dx: -precise, dy: 0))
        #expect(key("J", shift: true) == .move(dx: 0, dy: -precise))
        #expect(key("K", shift: true) == .move(dx: 0, dy: precise))
        #expect(key("L", shift: true) == .move(dx: precise, dy: 0))
    }

    @Test
    func arrowKeysMirrorTheMotionKeys() {
        let up = String(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!)
        let left = String(UnicodeScalar(UInt32(NSLeftArrowFunctionKey))!)
        #expect(
            SelectionKey.resolve(characters: up, modifiers: [.function, .numericPad])
                == .move(dx: 0, dy: SelectionKey.step)
        )
        #expect(
            SelectionKey.resolve(
                characters: left,
                modifiers: [.function, .numericPad, .shift]
            ) == .move(dx: -SelectionKey.preciseStep, dy: 0)
        )
    }

    @Test
    func modifiedAndUnknownKeysAreNotSelectionKeys() {
        #expect(SelectionKey.resolve(characters: "h", modifiers: .command) == nil)
        #expect(SelectionKey.resolve(characters: "h", modifiers: .control) == nil)
        #expect(key("z") == nil)
        #expect(key(nil ?? "") == nil)
    }

    @Test
    func questionMarkAsksForTheShortcutList() {
        #expect(key("?", shift: true) == .toggleHelp)
        var model = selection()
        // The view owns the panel, so the model treats it as a no-op.
        #expect(model.apply(.toggleHelp) == .ignored)
        #expect(model.cursor == CGPoint(x: 200, y: 150))
    }

    @Test
    func aFlippedSelectionInvertsVerticalMotionAndTopBottomJumps() {
        var model = KeyboardSelection(
            bounds: bounds,
            cursor: CGPoint(x: 200, y: 150),
            isFlipped: true
        )

        // k means visually up, which is a smaller y when y grows downward.
        _ = model.apply(.move(dx: 0, dy: SelectionKey.step))
        #expect(model.cursor == CGPoint(x: 200, y: 130))

        // gg reaches the visual top even though it resolves inside the model.
        _ = model.apply(.g)
        _ = model.apply(.g)
        #expect(model.cursor == CGPoint(x: 200, y: 0))

        _ = model.apply(.jump(.bottomEdge))
        #expect(model.cursor == CGPoint(x: 200, y: 300))

        // Horizontal jumps and the middle are unaffected by the flip.
        _ = model.apply(.jump(.rightEdge))
        #expect(model.cursor == CGPoint(x: 400, y: 300))
        _ = model.apply(.jump(.center))
        #expect(model.cursor == CGPoint(x: 400, y: 150))
    }

    @Test
    func cursorMovesAndClampsToTheBounds() {
        var model = selection(cursor: CGPoint(x: 1, y: 1))
        #expect(model.apply(.move(dx: -SelectionKey.step, dy: 0)) == .redraw)
        #expect(model.cursor == CGPoint(x: 0, y: 1))

        model = selection(cursor: CGPoint(x: 399, y: 299))
        _ = model.apply(.move(dx: 0, dy: SelectionKey.step))
        #expect(model.cursor == CGPoint(x: 399, y: 300))
    }

    @Test
    func countPrefixMultipliesTheNextMotionOnlyOnce() {
        var model = selection()
        #expect(model.apply(.digit(1)) == .ignored)
        #expect(model.apply(.digit(0)) == .ignored)
        #expect(model.apply(.move(dx: 0, dy: -1)) == .redraw)
        #expect(model.cursor == CGPoint(x: 200, y: 140))

        _ = model.apply(.move(dx: 0, dy: -1))
        #expect(model.cursor == CGPoint(x: 200, y: 139))
    }

    @Test
    func leadingZeroJumpsToTheLeftEdgeInsteadOfStartingACount() {
        var model = selection()
        #expect(model.apply(.digit(0)) == .redraw)
        #expect(model.cursor == CGPoint(x: 0, y: 150))
    }

    @Test
    func doubledGJumpsToTheTopAndASingleGIsCleared() {
        var model = selection()
        #expect(model.apply(.g) == .ignored)
        #expect(model.apply(.g) == .redraw)
        #expect(model.cursor == CGPoint(x: 200, y: 300))

        model = selection()
        #expect(model.apply(.g) == .ignored)
        _ = model.apply(.move(dx: 0, dy: -1))
        #expect(model.apply(.g) == .ignored)
        #expect(model.cursor == CGPoint(x: 200, y: 149))
    }

    @Test
    func jumpsMoveOnlyTheirOwnAxis() {
        var model = selection()
        _ = model.apply(.jump(.rightEdge))
        #expect(model.cursor == CGPoint(x: 400, y: 150))
        _ = model.apply(.jump(.bottomEdge))
        #expect(model.cursor == CGPoint(x: 400, y: 0))
        _ = model.apply(.jump(.center))
        #expect(model.cursor == CGPoint(x: 400, y: 150))
    }

    @Test
    func thereIsNoRectangleUntilTheCursorIsAnchored() {
        var model = selection()
        #expect(model.rect == nil)

        _ = model.apply(.toggleAnchor)
        _ = model.apply(.move(dx: 40, dy: -30))
        #expect(model.rect == CGRect(x: 200, y: 120, width: 40, height: 30))

        _ = model.apply(.toggleAnchor)
        #expect(model.rect == nil)
    }

    @Test
    func swappingEndsKeepsTheRectangleAndMovesTheOtherCorner() {
        var model = selection()
        _ = model.apply(.toggleAnchor)
        _ = model.apply(.move(dx: 40, dy: -30))
        #expect(model.apply(.swapEnds) == .redraw)
        #expect(model.cursor == CGPoint(x: 200, y: 150))
        #expect(model.anchor == CGPoint(x: 240, y: 120))
        #expect(model.rect == CGRect(x: 200, y: 120, width: 40, height: 30))

        _ = model.apply(.move(dx: -50, dy: 0))
        #expect(model.rect == CGRect(x: 150, y: 120, width: 90, height: 30))
    }

    @Test
    func swappingEndsWithoutAnAnchorIsIgnored() {
        var model = selection()
        #expect(model.apply(.swapEnds) == .ignored)
    }

    @Test
    func selectAllSpansTheWholeScreen() {
        var model = selection()
        _ = model.apply(.selectAll)
        #expect(model.rect == bounds)
    }

    @Test
    func confirmNeedsAnAnchoredRectangleAboveTheCropMinimum() {
        var model = selection()
        #expect(model.apply(.confirm) == .ignored)

        _ = model.apply(.toggleAnchor)
        #expect(model.apply(.confirm) == .ignored)

        _ = model.apply(.move(dx: 1, dy: -1))
        #expect(model.apply(.confirm) == .ignored)

        _ = model.apply(.move(dx: 9, dy: -9))
        #expect(model.apply(.confirm) == .confirmed(CGRect(x: 200, y: 140, width: 10, height: 10)))
    }

    @Test
    func clickingHandsTheCursorBackToTheMouseAndDropsTheAnchor() {
        var model = selection()
        _ = model.apply(.digit(9))
        _ = model.apply(.toggleAnchor)
        _ = model.apply(.move(dx: 40, dy: 0))

        model.place(at: CGPoint(x: 10, y: 20))
        #expect(model.cursor == CGPoint(x: 10, y: 20))
        #expect(model.anchor == nil)

        _ = model.apply(.move(dx: 1, dy: 0))
        #expect(model.cursor == CGPoint(x: 11, y: 20))
    }
}
