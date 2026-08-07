import AppKit
import Carbon

enum SelectionResult {
    case selected(CGRect, NSImage)
    case cancelled
    case failed(Error)
}

final class SelectionOverlayController {
    private var windows: [SelectionWindow] = []
    private var completion: ((SelectionResult) -> Void)?
    private var escapeMonitor: Any?
    private var finished = false

    func begin(completion: @escaping (SelectionResult) -> Void) {
        self.completion = completion

        let screens = NSScreen.screens
        let snapshots: [ScreenSnapshot]
        do {
            snapshots = try screens.map(ScreenCapture.snapshot)
        } catch {
            finish(.failed(error))
            return
        }

        for (screen, snapshot) in zip(screens, snapshots) {
            let window = SelectionWindow(
                screen: screen,
                snapshot: snapshot
            ) { [weak self] rect, image in
                self?.finish(.selected(rect, image))
            }
            windows.append(window)
            window.orderFrontRegardless()
        }

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                self?.finish(.cancelled)
                return nil
            }
            return event
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(_ result: SelectionResult) {
        guard !finished else { return }
        finished = true

        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()

        let callback = completion
        completion = nil
        DispatchQueue.main.async {
            callback?(result)
        }
    }
}

final class SelectionWindow: NSWindow {
    init(
        screen: NSScreen,
        snapshot: ScreenSnapshot,
        onSelection: @escaping (CGRect, NSImage) -> Void
    ) {
        let view = SelectionView(
            screen: screen,
            snapshot: snapshot,
            onSelection: onSelection
        )
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = view
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
}

final class SelectionView: NSView {
    private let targetScreen: NSScreen
    private let snapshot: ScreenSnapshot
    private let onSelection: (CGRect, NSImage) -> Void
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

    init(
        screen: NSScreen,
        snapshot: ScreenSnapshot,
        onSelection: @escaping (CGRect, NSImage) -> Void
    ) {
        targetScreen = screen
        self.snapshot = snapshot
        self.onSelection = onSelection
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        dragCurrent = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragStart else { return }
        let end = convert(event.locationInWindow, from: nil)
        let localRect = CGRect(
            x: min(dragStart.x, end.x),
            y: min(dragStart.y, end.y),
            width: abs(end.x - dragStart.x),
            height: abs(end.y - dragStart.y)
        ).integral

        guard localRect.width >= 2, localRect.height >= 2 else {
            self.dragStart = nil
            dragCurrent = nil
            needsDisplay = true
            return
        }

        let rect = quartzRect(for: localRect)
        guard let image = snapshot.crop(to: rect) else { return }
        onSelection(rect, image)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        snapshot.image.draw(in: bounds)
        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()

        guard let dragStart, let dragCurrent else { return }

        let selection = CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        )

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selection).addClip()
        snapshot.image.draw(in: bounds)
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }

    private func quartzRect(for localRect: CGRect) -> CGRect {
        guard
            let screenNumber = targetScreen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber
        else {
            return localRect
        }

        let displayBounds = CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value))
        return CGRect(
            x: displayBounds.minX + localRect.minX,
            y: displayBounds.minY + (bounds.height - localRect.maxY),
            width: localRect.width,
            height: localRect.height
        ).integral
    }
}
