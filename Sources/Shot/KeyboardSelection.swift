import AppKit

/// A key press understood by the keyboard-driven selection overlay.
///
/// Movement deltas are expressed in `SelectionView` coordinates, which are
/// **not** flipped: `k` moves toward the top of the screen by increasing `y`.
enum SelectionKey: Equatable {
    enum Jump: Equatable {
        case leftEdge
        case rightEdge
        case topEdge
        case bottomEdge
        case center
    }

    case move(dx: CGFloat, dy: CGFloat)
    case jump(Jump)
    case digit(Int)
    /// Half of the `gg` sequence. `KeyboardSelection` pairs them up.
    case g
    case toggleAnchor
    case swapEnds
    case selectAll
    case confirm
    case cancel
    case toggleHelp

    /// Plain motion covers ground; shift drops to pixel precision.
    static let step: CGFloat = 20
    static let preciseStep: CGFloat = 1

    static func resolve(
        characters: String?,
        modifiers: NSEvent.ModifierFlags
    ) -> SelectionKey? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        guard flags.intersection([.command, .control, .option]).isEmpty else {
            return nil
        }
        guard let character = characters?.first else { return nil }

        // Arrow keys carry .function and .numericPad, so they are matched by
        // scalar before the printable keys.
        if let scalar = character.unicodeScalars.first?.value,
           let arrow = arrow(for: scalar, precise: flags.contains(.shift)) {
            return arrow
        }

        switch character {
        case "h": return .move(dx: -step, dy: 0)
        case "l": return .move(dx: step, dy: 0)
        case "j": return .move(dx: 0, dy: -step)
        case "k": return .move(dx: 0, dy: step)
        case "H": return .move(dx: -preciseStep, dy: 0)
        case "L": return .move(dx: preciseStep, dy: 0)
        case "J": return .move(dx: 0, dy: -preciseStep)
        case "K": return .move(dx: 0, dy: preciseStep)
        case "$": return .jump(.rightEdge)
        case "G": return .jump(.bottomEdge)
        case "M": return .jump(.center)
        case "g": return .g
        case "v", " ": return .toggleAnchor
        case "o": return .swapEnds
        case "a": return .selectAll
        case "y", "\r", "\n", "\u{3}": return .confirm
        case "q", "\u{1b}": return .cancel
        case "?": return .toggleHelp
        default:
            guard let digit = character.wholeNumberValue, (0...9).contains(digit) else {
                return nil
            }
            return .digit(digit)
        }
    }

    private static func arrow(for scalar: UInt32, precise: Bool) -> SelectionKey? {
        let distance = precise ? preciseStep : step
        switch scalar {
        case UInt32(NSLeftArrowFunctionKey): return .move(dx: -distance, dy: 0)
        case UInt32(NSRightArrowFunctionKey): return .move(dx: distance, dy: 0)
        case UInt32(NSDownArrowFunctionKey): return .move(dx: 0, dy: -distance)
        case UInt32(NSUpArrowFunctionKey): return .move(dx: 0, dy: distance)
        default: return nil
        }
    }
}

/// Visual-mode style selection: a cursor that moves freely until it is
/// anchored, after which motion resizes the selection.
struct KeyboardSelection {
    enum Outcome: Equatable {
        case ignored
        case redraw
        case cancelled
        case confirmed(CGRect)
    }

    /// Matches the floor `ScreenSnapshot.crop(to:)` already enforces.
    static let minimumSide: CGFloat = 2

    let bounds: CGRect
    /// True where y grows downward, as on the editor canvas. Motion keys and
    /// the top and bottom jumps are named for what the user sees, so they
    /// invert here.
    let isFlipped: Bool
    private(set) var cursor: CGPoint
    private(set) var anchor: CGPoint?
    private var count: Int?
    private var awaitingG = false

    init(bounds: CGRect, cursor: CGPoint, isFlipped: Bool = false) {
        self.bounds = bounds
        self.isFlipped = isFlipped
        self.cursor = Self.clamp(cursor, to: bounds)
    }

    var rect: CGRect? {
        guard let anchor else { return nil }
        return CGRect(spanning: anchor, cursor).integral
    }

    /// Moves the cursor to a mouse click and drops any pending state, so the
    /// user can switch between mouse and keyboard mid-selection.
    mutating func place(at point: CGPoint) {
        cursor = Self.clamp(point, to: bounds)
        anchor = nil
        count = nil
        awaitingG = false
    }

    mutating func apply(_ key: SelectionKey) -> Outcome {
        // `gg` is the only two-key sequence; anything else clears the pending g.
        let hadPendingG = awaitingG
        awaitingG = false

        switch key {
        case let .move(dx, dy):
            let repeatCount = CGFloat(count ?? 1)
            let verticalStep = isFlipped ? -dy : dy
            count = nil
            cursor = Self.clamp(
                CGPoint(
                    x: cursor.x + dx * repeatCount,
                    y: cursor.y + verticalStep * repeatCount
                ),
                to: bounds
            )
            return .redraw

        case let .jump(jump):
            count = nil
            cursor = position(for: jump)
            return .redraw

        case let .digit(digit):
            // A leading zero is vim's start-of-line, not the start of a count.
            if digit == 0, count == nil {
                cursor = position(for: .leftEdge)
                return .redraw
            }
            count = min((count ?? 0) * 10 + digit, 99_999)
            return .ignored

        case .g:
            guard hadPendingG else {
                awaitingG = true
                return .ignored
            }
            count = nil
            cursor = position(for: .topEdge)
            return .redraw

        case .toggleAnchor:
            count = nil
            anchor = anchor == nil ? cursor : nil
            return .redraw

        case .swapEnds:
            count = nil
            guard let anchor else { return .ignored }
            self.anchor = cursor
            cursor = anchor
            return .redraw

        case .selectAll:
            count = nil
            anchor = CGPoint(x: bounds.minX, y: bounds.minY)
            cursor = CGPoint(x: bounds.maxX, y: bounds.maxY)
            return .redraw

        case .confirm:
            count = nil
            guard
                let rect,
                rect.width >= Self.minimumSide,
                rect.height >= Self.minimumSide
            else { return .ignored }
            return .confirmed(rect)

        case .cancel:
            return .cancelled

        case .toggleHelp:
            // Presentation only; the view that owns the model handles it.
            return .ignored
        }
    }

    private func position(for jump: SelectionKey.Jump) -> CGPoint {
        switch jump {
        case .leftEdge: return CGPoint(x: bounds.minX, y: cursor.y)
        case .rightEdge: return CGPoint(x: bounds.maxX, y: cursor.y)
        case .topEdge: return CGPoint(x: cursor.x, y: isFlipped ? bounds.minY : bounds.maxY)
        case .bottomEdge: return CGPoint(x: cursor.x, y: isFlipped ? bounds.maxY : bounds.minY)
        case .center: return CGPoint(x: cursor.x, y: bounds.midY)
        }
    }

    private static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }
}
