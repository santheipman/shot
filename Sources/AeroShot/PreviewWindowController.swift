import AppKit

final class PreviewWindowController: NSWindowController, NSWindowDelegate, EditorWindow {
    var onClose: ((Int) -> Void)?
    var identifier: Int? { window?.windowNumber }

    init(image: NSImage, captureRect: CGRect) {
        let model = AnnotationEditorModel(sourceImage: image)

        let panel = EditorPanel(
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
        panel.minSize = NSSize(width: 480, height: 240)
        panel.titlebarAppearsTransparent = false
        panel.titlebarSeparatorStyle = .line
        panel.hasShadow = true
        panel.backgroundColor = .windowBackgroundColor

        super.init(window: panel)
        panel.delegate = self
        let editor = PreviewViewController(model: model)
        editor.onFinish = { [weak panel, weak editor] in
            guard let flattened = editor?.flattenedImage() else {
                Self.showError(
                    title: "Copy failed",
                    message: "AeroShot couldn’t prepare the edited image.",
                    from: panel
                )
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.writeObjects([flattened]) else {
                Self.showError(
                    title: "Copy failed",
                    message: "AeroShot couldn’t write the edited image to the clipboard.",
                    from: panel
                )
                return
            }
            EventLog.shared.write("edited_image_copied")
            panel?.close()
        }
        editor.onSave = { [weak panel, weak editor] in
            guard let flattened = editor?.flattenedImage() else {
                Self.showError(
                    title: "Save failed",
                    message: "AeroShot couldn’t prepare the edited image.",
                    from: panel
                )
                return
            }
            Self.save(image: flattened, from: panel)
        }
        panel.onEscape = { [weak editor] in editor?.finish() }
        panel.onUndo = { [weak editor] in editor?.undo() }
        panel.onShortcut = { [weak editor] shortcut in
            switch shortcut {
            case .save:
                editor?.save()
            case let .selectTool(tool):
                editor?.selectTool(tool)
            }
        }
        panel.contentViewController = editor

        sizeAndPosition(panel: panel, image: image, captureRect: captureRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        guard let window else { return }
        // Mark the newly created editor as key before activating AeroShot.
        // AppKit then brings forward this key window rather than an older
        // editor that belongs to another workspace.
        window.makeKeyAndOrderFront(sender)
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(sender)
        }
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
        let maximum = CGSize(width: visibleFrame.width * 0.78, height: visibleFrame.height * 0.78)
        let minimum = CGSize(width: 560, height: 280)
        let toolbarHeight: CGFloat = 56
        let imageRatio = max(image.size.width / max(image.size.height, 1), 0.1)

        var contentWidth = min(max(image.size.width, minimum.width), maximum.width)
        var imageHeight = contentWidth / imageRatio
        if imageHeight + toolbarHeight > maximum.height {
            imageHeight = maximum.height - toolbarHeight
            contentWidth = imageHeight * imageRatio
        }
        panel.setContentSize(
            CGSize(
                width: max(contentWidth, minimum.width),
                height: max(imageHeight + toolbarHeight, minimum.height)
            )
        )
        panel.setFrameOrigin(
            CGPoint(
                x: visibleFrame.midX - panel.frame.width / 2,
                y: visibleFrame.midY - panel.frame.height / 2
            )
        )
    }

    private static func save(image: NSImage, from window: NSWindow?) {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/screenshot", isDirectory: true)
        let url = ScreenshotFileNamer.availableURL(
            in: directory,
            timestamp: fileTimestamp()
        )
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            EventLog.shared.write("image_save_failed reason=encoding")
            showError(
                title: "Save failed",
                message: "AeroShot couldn’t encode the edited image as PNG.",
                from: window
            )
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try png.write(to: url, options: .atomic)
            EventLog.shared.write("image_saved path=\(url.path)")
        } catch {
            EventLog.shared.write("image_save_failed error=\(error.localizedDescription)")
            showError(
                title: "Save failed",
                message: "AeroShot couldn’t save the image.\n\n\(error.localizedDescription)",
                from: window
            )
        }
    }

    private static func showError(
        title: String,
        message: String,
        from window: NSWindow?
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
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

private final class EditorPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onUndo: (() -> Void)?
    var onShortcut: ((EditorShortcut) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            onUndo?()
            return
        }
        if !event.isARepeat,
           let shortcut = EditorShortcut.resolve(
               characters: event.charactersIgnoringModifiers,
               modifiers: event.modifierFlags
           ) {
            onShortcut?(shortcut)
            return
        }
        super.keyDown(with: event)
    }
}

private final class PreviewViewController: NSViewController {
    private let model: AnnotationEditorModel
    private let canvas: AnnotationCanvasView
    private let toolControl: NSSegmentedControl
    var onFinish: (() -> Void)?
    var onSave: (() -> Void)?

    init(model: AnnotationEditorModel) {
        self.model = model
        canvas = AnnotationCanvasView(model: model)
        let toolImages = [
            NSImage(systemSymbolName: "pencil", accessibilityDescription: "Pencil"),
            NSImage(systemSymbolName: "rectangle", accessibilityDescription: "Rectangle"),
            NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: "Arrow"),
        ].compactMap { $0 }
        toolControl = NSSegmentedControl(
            images: toolImages,
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        super.init(nibName: nil, bundle: nil)
        toolControl.target = self
        toolControl.action = #selector(changeTool(_:))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        canvas.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(canvas)

        toolControl.selectedSegment = 0
        toolControl.segmentStyle = .texturedRounded
        toolControl.setAccessibilityLabel("Annotation tool")
        toolControl.setToolTip("Pencil (P)", forSegment: 0)
        toolControl.setToolTip("Rectangle (R)", forSegment: 1)
        toolControl.setToolTip("Arrow (A)", forSegment: 2)

        let color = NSPopUpButton()
        color.addItems(withTitles: AnnotationColor.allCases.map(\.rawValue))
        color.toolTip = "Color"
        color.target = self
        color.action = #selector(changeColor(_:))

        let thickness = NSPopUpButton()
        thickness.addItems(withTitles: AnnotationThickness.allCases.map(\.rawValue))
        thickness.selectItem(withTitle: model.thickness.rawValue)
        thickness.toolTip = "Line thickness"
        thickness.target = self
        thickness.action = #selector(changeThickness(_:))

        let save = NSButton(title: "Save", target: self, action: #selector(save))
        save.toolTip = "Save (S)"

        let controls = NSStackView(views: [
            toolControl, color, thickness, NSView(), save,
        ])
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.orientation = .horizontal
        controls.spacing = 8
        controls.alignment = .centerY
        controls.setHuggingPriority(.defaultLow, for: .horizontal)

        let toolbar = NSVisualEffectView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.material = .headerView
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active
        toolbar.addSubview(controls)
        root.addSubview(toolbar)

        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: root.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: toolbar.topAnchor),

            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 52),

            controls.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
            controls.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
            controls.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            controls.heightAnchor.constraint(equalToConstant: 32),
        ])
        view = root
    }

    func flattenedImage() -> NSImage? {
        AnnotationRenderer.flattenedImage(
            source: model.sourceImage,
            annotations: model.annotations
        )
    }

    func finish() {
        onFinish?()
    }

    @objc func undo() {
        if model.undo() {
            canvas.needsDisplay = true
        }
    }

    @objc func save() {
        onSave?()
    }

    func selectTool(_ tool: AnnotationTool) {
        model.tool = tool
        if let index = AnnotationTool.allCases.firstIndex(of: tool) {
            toolControl.selectedSegment = index
        }
    }

    @objc private func changeTool(_ sender: NSSegmentedControl) {
        let tools = AnnotationTool.allCases
        guard tools.indices.contains(sender.selectedSegment) else { return }
        selectTool(tools[sender.selectedSegment])
    }

    @objc private func changeColor(_ sender: NSPopUpButton) {
        model.color = AnnotationColor(rawValue: sender.titleOfSelectedItem ?? "") ?? .red
    }

    @objc private func changeThickness(_ sender: NSPopUpButton) {
        model.thickness =
            AnnotationThickness(rawValue: sender.titleOfSelectedItem ?? "") ?? .medium
    }
}

private final class AnnotationCanvasView: NSView {
    private let model: AnnotationEditorModel
    private var draft: AnnotationShape?

    init(model: AnnotationEditorModel) {
        self.model = model
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
        let imageRect = AnnotationRenderer.aspectFitRect(
            imageSize: model.sourceImage.size,
            in: bounds
        )
        model.sourceImage.draw(
            in: imageRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        var annotations = model.annotations
        if let draft {
            annotations.append(
                Annotation(
                    shape: draft,
                    style: AnnotationStyle(color: model.color, thickness: model.thickness)
                )
            )
        }
        AnnotationRenderer.draw(
            annotations: annotations,
            in: context,
            imageSize: model.sourceImage.size,
            destinationRect: imageRect
        )
    }

    override func mouseDown(with event: NSEvent) {
        guard let point = imagePoint(for: event) else { return }
        switch model.tool {
        case .pencil: draft = .pencil([point])
        case .rectangle: draft = .rectangle(start: point, end: point)
        case .arrow: draft = .arrow(start: point, end: point)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let point = imagePoint(for: event, clamped: true) else { return }
        updateDraft(with: point)
    }

    override func mouseUp(with event: NSEvent) {
        if let point = imagePoint(for: event, clamped: true) {
            updateDraft(with: point)
        }
        guard let draft else { return }
        model.commit(draft)
        self.draft = nil
        needsDisplay = true
    }

    private func updateDraft(with point: CGPoint) {
        guard let draft else { return }
        switch draft {
        case var .pencil(points):
            if points.last != point {
                points.append(point)
            }
            self.draft = .pencil(points)
        case let .rectangle(start, _):
            self.draft = .rectangle(start: start, end: point)
        case let .arrow(start, _):
            self.draft = .arrow(start: start, end: point)
        }
        needsDisplay = true
    }

    private func imagePoint(for event: NSEvent, clamped: Bool = false) -> CGPoint? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let imageRect = AnnotationRenderer.aspectFitRect(
            imageSize: model.sourceImage.size,
            in: bounds
        )
        if clamped {
            return AnnotationRenderer.clampedImagePoint(
                from: viewPoint,
                imageRect: imageRect,
                imageSize: model.sourceImage.size
            )
        }
        return AnnotationRenderer.imagePoint(
            from: viewPoint,
            imageRect: imageRect,
            imageSize: model.sourceImage.size
        )
    }
}
