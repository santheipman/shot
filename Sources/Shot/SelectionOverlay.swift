import AppKit

enum SelectionResult {
    case selected(CGRect, NSImage)
    case cancelled
    case failed(Error)
}

final class SelectionOverlayController {
    private let keyboardEnabled: Bool
    private var windows: [SelectionWindow] = []
    private weak var activeView: SelectionView?
    private var completion: ((SelectionResult) -> Void)?
    private var keyMonitor: Any?
    private var finished = false
    private var cursorHidden = false

    init(keyboardEnabled: Bool = false) {
        self.keyboardEnabled = keyboardEnabled
    }

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
            window.selectionView.onMouseActivity = { [weak self] in
                self?.showCursor()
            }
            windows.append(window)
            window.orderFrontRegardless()
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }

        NSApp.activate(ignoringOtherApps: true)

        if keyboardEnabled {
            startKeyboardSelection(on: screens)
        }
    }

    /// Puts a keyboard cursor on the screen under the pointer. The other
    /// screens keep their dimmed overlay so Escape and the framing stay
    /// consistent, but the cursor never leaves this one display.
    private func startKeyboardSelection(on screens: [NSScreen]) {
        let mouseLocation = NSEvent.mouseLocation
        let index = screens.firstIndex { $0.frame.contains(mouseLocation) } ?? 0
        guard windows.indices.contains(index) else { return }

        let window = windows[index]
        let frame = screens[index].frame
        let start = frame.contains(mouseLocation)
            ? CGPoint(x: mouseLocation.x - frame.minX, y: mouseLocation.y - frame.minY)
            : nil

        window.selectionView.beginKeyboardSelection(at: start)
        activeView = window.selectionView
        claimKeyboardFocus(for: window)
    }

    /// The key monitor only sees events dispatched to Shot, so the overlay is
    /// useless from the keyboard unless Shot is the active app. Another app
    /// that holds activation - a screen recorder, for instance - can win the
    /// first attempt, so this retries once the run loop has settled.
    private func claimKeyboardFocus(for window: SelectionWindow) {
        window.makeKeyAndOrderFront(nil)
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        logFocus("keyboard_focus_requested", window: window)

        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, !self.finished, !window.isKeyWindow else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            self.logFocus("keyboard_focus_retried", window: window)
        }
    }

    private func logFocus(_ event: String, window: NSWindow) {
        guard EventLog.shared.isFileLoggingEnabled else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
        EventLog.shared.write(
            "\(event) app_active=\(NSApp.isActive) key_window=\(window.isKeyWindow) " +
                "frontmost=\(frontmost)"
        )
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.isEscapeKey {
            if activeView?.dismissHelp() == true { return nil }
            finish(.cancelled)
            return nil
        }
        EventLog.shared.write(
            "selection_key_seen characters=\(event.charactersIgnoringModifiers ?? "none")"
        )
        guard let activeView else {
            EventLog.shared.write("selection_key_dropped reason=no_active_view")
            return event
        }
        // Leave app-level equivalents such as Command-Q alone.
        guard !event.modifierFlags.contains(.command) else {
            EventLog.shared.write("selection_key_dropped reason=command_modifier")
            return event
        }
        guard let key = SelectionKey.resolve(
            characters: event.charactersIgnoringModifiers,
            modifiers: event.modifierFlags
        ) else {
            EventLog.shared.write("selection_key_dropped reason=unbound")
            // Swallow the rest so the borderless overlay does not beep.
            return nil
        }

        if key == .toggleHelp {
            activeView.toggleHelp()
            return nil
        }

        hideCursor()
        let outcome = activeView.apply(key)
        EventLog.shared.write(
            "selection_key_applied outcome=\(outcome) \(activeView.cursorDescription)"
        )
        switch outcome {
        case let .confirmed(localRect):
            activeView.complete(localRect: localRect)
        case .cancelled:
            finish(.cancelled)
        case .redraw, .ignored:
            break
        }
        return nil
    }

    private func finish(_ result: SelectionResult) {
        guard !finished else { return }
        finished = true

        showCursor()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        activeView = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()

        let callback = completion
        completion = nil
        DispatchQueue.main.async {
            callback?(result)
        }
    }

    private func hideCursor() {
        guard !cursorHidden else { return }
        cursorHidden = true
        NSCursor.hide()
    }

    private func showCursor() {
        guard cursorHidden else { return }
        cursorHidden = false
        NSCursor.unhide()
    }
}

final class SelectionWindow: NSWindow {
    let selectionView: SelectionView

    init(
        screen: NSScreen,
        snapshot: ScreenSnapshot,
        onSelection: @escaping (CGRect, NSImage) -> Void
    ) {
        selectionView = SelectionView(
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
        contentView = selectionView
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
    private var keyboard: KeyboardSelection?
    private var showsHelp = false
    private var trackingArea: NSTrackingArea?

    var onMouseActivity: (() -> Void)?

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

    // MARK: - Keyboard

    var cursorDescription: String {
        guard let keyboard else { return "cursor=none" }
        let anchor = keyboard.anchor.map { "\(Int($0.x)),\(Int($0.y))" } ?? "none"
        return "cursor=\(Int(keyboard.cursor.x)),\(Int(keyboard.cursor.y)) "
            + "anchor=\(anchor) bounds=\(Int(bounds.width))x\(Int(bounds.height)) "
            + "visible=\(window?.isVisible == true)"
    }

    func beginKeyboardSelection(at point: CGPoint?) {
        keyboard = KeyboardSelection(
            bounds: bounds,
            cursor: point ?? CGPoint(x: bounds.midX, y: bounds.midY)
        )
        needsDisplay = true
        EventLog.shared.write("keyboard_selection_begun \(cursorDescription)")
    }

    func toggleHelp() {
        showsHelp.toggle()
        needsDisplay = true
    }

    @discardableResult
    func dismissHelp() -> Bool {
        guard showsHelp else { return false }
        showsHelp = false
        needsDisplay = true
        return true
    }

    func apply(_ key: SelectionKey) -> KeyboardSelection.Outcome {
        guard var model = keyboard else { return .ignored }
        let outcome = model.apply(key)
        keyboard = model
        if outcome == .redraw {
            needsDisplay = true
        }
        return outcome
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseActivity?()
    }

    override func mouseDown(with event: NSEvent) {
        onMouseActivity?()
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        dragCurrent = point
        keyboard?.place(at: point)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragStart else { return }
        let end = convert(event.locationInWindow, from: nil)
        let localRect = CGRect(spanning: dragStart, end).integral

        guard
            localRect.width >= KeyboardSelection.minimumSide,
            localRect.height >= KeyboardSelection.minimumSide
        else {
            self.dragStart = nil
            dragCurrent = nil
            needsDisplay = true
            return
        }

        complete(localRect: localRect)
    }

    /// Shared tail of the mouse and keyboard paths.
    func complete(localRect: CGRect) {
        let rect = quartzRect(for: localRect)
        guard let image = snapshot.crop(to: rect) else { return }
        onSelection(rect, image)
    }

    // MARK: - Drawing

    private var selectionRect: CGRect? {
        if let dragStart, let dragCurrent {
            return CGRect(spanning: dragStart, dragCurrent)
        }
        return keyboard?.rect
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        snapshot.image.draw(in: bounds)
        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()

        let selection = selectionRect
        if let selection {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selection).addClip()
            snapshot.image.draw(in: bounds)
            NSGraphicsContext.restoreGraphicsState()

            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }

        guard let keyboard else { return }

        if selection == nil {
            KeyboardChrome.drawCrosshair(at: keyboard.cursor, in: bounds)
        }
        KeyboardChrome.drawBadge(
            selection.map { "\(Int($0.width)) × \(Int($0.height))" }
                ?? "\(Int(keyboard.cursor.x)), \(Int(keyboard.cursor.y))",
            near: keyboard.cursor,
            in: bounds
        )
        drawHint()

        if showsHelp {
            KeyboardChrome.drawHelp(
                title: "Keyboard selection",
                rows: Self.helpRows,
                in: bounds
            )
        }
    }

    private static let helpRows: [(keys: String, action: String)] = [
        ("hjkl / arrows", "Move \(Int(SelectionKey.step)) pt"),
        ("HJKL / ⇧arrows", "Move \(Int(SelectionKey.preciseStep)) pt"),
        ("10j  300l", "Repeat the next motion"),
        ("0  $", "Left, right edge"),
        ("gg  G  M", "Top, bottom, middle"),
        ("v  space", "Set or drop the anchor"),
        ("o", "Swap anchor and cursor"),
        ("a", "Anchor the whole screen"),
        ("⏎  y", "Capture"),
        ("esc  q", "Cancel"),
        ("?", "Hide this"),
    ]

    private func drawHint() {
        let text = "hjkl move · v anchor · ⏎ capture · esc cancel · ? shortcuts"
        let size = KeyboardChrome.labelSize(text)
        KeyboardChrome.drawLabel(
            text,
            in: CGRect(
                x: bounds.midX - size.width / 2,
                y: bounds.minY + 28,
                width: size.width,
                height: size.height
            )
        )
    }

    private func quartzRect(for localRect: CGRect) -> CGRect {
        guard let displayID = targetScreen.displayID else {
            return localRect
        }

        let displayBounds = CGDisplayBounds(displayID)
        return CGRect(
            x: displayBounds.minX + localRect.minX,
            y: displayBounds.minY + (bounds.height - localRect.maxY),
            width: localRect.width,
            height: localRect.height
        ).integral
    }
}
