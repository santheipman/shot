import AppKit

final class PinWindowController: NSWindowController, NSWindowDelegate, PinWindow {
    var onClose: ((Int) -> Void)?
    var identifier: Int? { window?.windowNumber }

    init(image: NSImage, captureRect: CGRect) {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isRestorable = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.contentAspectRatio = image.size

        super.init(window: panel)
        panel.delegate = self
        panel.contentView = PinContentView(image: image) { [weak panel] in
            panel?.close()
        }

        sizeAndPosition(panel: panel, image: image, captureRect: captureRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let windowNumber = window.windowNumber
        window.delegate = nil
        self.window = nil
        let callback = onClose
        onClose = nil
        DispatchQueue.main.async {
            callback?(windowNumber)
        }
    }

    private func sizeAndPosition(panel: NSPanel, image: NSImage, captureRect: CGRect) {
        let screen = Self.screen(containingQuartzPoint: captureRect.origin) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let maximum = CGSize(
            width: visibleFrame.width * 0.7,
            height: visibleFrame.height * 0.7
        )
        let imageRatio = max(image.size.width / max(image.size.height, 1), 0.1)

        var size = image.size
        if size.width > maximum.width {
            size.width = maximum.width
            size.height = size.width / imageRatio
        }
        if size.height > maximum.height {
            size.height = maximum.height
            size.width = size.height * imageRatio
        }

        let minimumWidth = min(120, size.width)
        panel.minSize = NSSize(width: minimumWidth, height: minimumWidth / imageRatio)
        panel.setContentSize(size)
        panel.setFrameOrigin(
            CGPoint(
                x: visibleFrame.midX - panel.frame.width / 2,
                y: visibleFrame.midY - panel.frame.height / 2
            )
        )
    }

    private static func screen(containingQuartzPoint point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard
                let number = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber
            else {
                return false
            }
            return CGDisplayBounds(CGDirectDisplayID(number.uint32Value)).contains(point)
        }
    }
}

private final class PinContentView: NSView {
    private let image: NSImage
    private let closeButton = NSButton()
    private let closeTarget: ClosureTarget
    private var trackingArea: NSTrackingArea?

    init(image: NSImage, onClose: @escaping () -> Void) {
        self.image = image
        closeTarget = ClosureTarget(action: onClose)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.masksToBounds = true

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.title = "×"
        closeButton.font = .systemFont(ofSize: 16, weight: .semibold)
        closeButton.isBordered = false
        closeButton.bezelStyle = .circular
        closeButton.contentTintColor = .white
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        closeButton.layer?.cornerRadius = 10
        closeButton.isHidden = true
        closeButton.target = closeTarget
        closeButton.action = #selector(ClosureTarget.invoke)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(
            in: bounds,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        closeButton.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.isHidden = true
    }

    override var mouseDownCanMoveWindow: Bool { true }
}

private final class ClosureTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invoke() {
        action()
    }
}
