import AppKit

final class PreviewWindowController: NSWindowController, NSWindowDelegate, EditorWindow {
    var onClose: ((Int) -> Void)?
    var identifier: Int? { window?.windowNumber }

    private let image: NSImage
    init(image: NSImage, captureRect: CGRect) {
        self.image = image

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "AeroShot"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isRestorable = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.minSize = NSSize(width: 280, height: 180)
        panel.titlebarAppearsTransparent = true

        super.init(window: panel)
        panel.delegate = self
        panel.contentViewController = PreviewViewController(
            image: image,
            onCopy: { Self.copyToPasteboard(image) },
            onSave: { Self.save(image: image, from: panel) },
            onClose: { panel.close() }
        )

        sizeAndPosition(panel: panel, image: image, captureRect: captureRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        guard let panel = window else { return }
        // Present only this newly created editor. App-wide activation can raise
        // an existing editor from a different workspace.
        panel.makeKeyAndOrderFront(sender)
    }

    func present() {
        showWindow(nil)
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
            width: visibleFrame.width * 0.72,
            height: visibleFrame.height * 0.72
        )
        let minimum = CGSize(width: 320, height: 220)
        let toolbarHeight: CGFloat = 52
        let imageRatio = max(image.size.width / max(image.size.height, 1), 0.1)

        var contentWidth = min(max(image.size.width, minimum.width), maximum.width)
        var imageHeight = contentWidth / imageRatio
        if imageHeight + toolbarHeight > maximum.height {
            imageHeight = maximum.height - toolbarHeight
            contentWidth = imageHeight * imageRatio
        }

        let contentSize = CGSize(
            width: max(contentWidth, minimum.width),
            height: max(imageHeight + toolbarHeight, minimum.height)
        )
        panel.setContentSize(contentSize)

        let frame = panel.frame
        let origin = CGPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.midY - frame.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    private static func copyToPasteboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        EventLog.shared.write("image_copied")
    }

    private static func save(image: NSImage, from window: NSWindow) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "AeroShot \(Self.fileTimestamp()).png"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            guard
                let tiff = image.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiff),
                let png = bitmap.representation(using: .png, properties: [:])
            else {
                EventLog.shared.write("image_save_failed encoding")
                return
            }

            do {
                try png.write(to: url, options: .atomic)
                EventLog.shared.write("image_saved path=\(url.path)")
            } catch {
                EventLog.shared.write("image_save_failed error=\(error.localizedDescription)")
            }
        }
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: Date())
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

private final class PreviewViewController: NSViewController {
    private let image: NSImage
    private let onCopy: () -> Void
    private let onSave: () -> Void
    private let onClose: () -> Void

    init(
        image: NSImage,
        onCopy: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.image = image
        self.onCopy = onCopy
        self.onSave = onSave
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        root.addSubview(imageView)

        let copy = NSButton(title: "Copy", target: self, action: #selector(copyImage))
        let save = NSButton(title: "Save…", target: self, action: #selector(saveImage))
        let close = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        close.keyEquivalent = "\u{1b}"

        let controls = NSStackView(views: [copy, save, close])
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.orientation = .horizontal
        controls.spacing = 8
        controls.alignment = .centerY
        root.addSubview(controls)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: root.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -8),

            controls.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            controls.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            controls.heightAnchor.constraint(equalToConstant: 32),
        ])

        view = root
    }

    @objc private func copyImage() {
        onCopy()
    }

    @objc private func saveImage() {
        onSave()
    }

    @objc private func closeWindow() {
        onClose()
    }
}
