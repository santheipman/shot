import AppKit

final class PreviewWindowController: ManagedWindowController {
    init(image: NSImage, captureRect: CGRect) {
        let model = AnnotationEditorModel(sourceImage: image)

        let panel = EditorPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Shot"
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
                    message: "Shot couldn’t prepare the edited image.",
                    from: panel
                )
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.writeObjects([flattened]) else {
                Self.showError(
                    title: "Copy failed",
                    message: "Shot couldn’t write the edited image to the clipboard.",
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
                    message: "Shot couldn’t prepare the edited image.",
                    from: panel
                )
                return
            }
            Self.save(image: flattened, from: panel)
        }
        panel.onEscape = { [weak editor] in editor?.handleEscape() }
        panel.onUndo = { [weak editor] in editor?.undo() }
        panel.shouldHandleCanvasShortcuts = { [weak editor] in
            editor?.isEditingText == false
        }
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

    private func sizeAndPosition(panel: NSPanel, image: NSImage, captureRect: CGRect) {
        let visibleFrame = Self.visibleFrame(nearQuartzPoint: captureRect.origin)
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
        centerWindow(in: visibleFrame)
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
                message: "Shot couldn’t encode the edited image as PNG.",
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
                message: "Shot couldn’t save the image.\n\n\(error.localizedDescription)",
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
}

private final class EditorPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onUndo: (() -> Void)?
    var onShortcut: ((EditorShortcut) -> Void)?
    var shouldHandleCanvasShortcuts: (() -> Bool)?

    override func keyDown(with event: NSEvent) {
        if event.isEscapeKey {
            onEscape?()
            return
        }
        guard shouldHandleCanvasShortcuts?() != false else {
            super.keyDown(with: event)
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
    private let styleControl: NSPopUpButton
    var onFinish: (() -> Void)?
    var onSave: (() -> Void)?
    var isEditingText: Bool { canvas.isEditingText }

    init(model: AnnotationEditorModel) {
        self.model = model
        canvas = AnnotationCanvasView(model: model)
        styleControl = NSPopUpButton()
        let toolImages = [
            NSImage(systemSymbolName: "pencil", accessibilityDescription: "Pencil"),
            NSImage(systemSymbolName: "rectangle", accessibilityDescription: "Rectangle"),
            NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: "Arrow"),
            NSImage(systemSymbolName: "textformat", accessibilityDescription: "Text"),
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
        toolControl.setToolTip("Text (T)", forSegment: 3)

        let color = NSPopUpButton()
        color.addItems(withTitles: AnnotationColor.allCases.map(\.rawValue))
        color.toolTip = "Color"
        color.target = self
        color.action = #selector(changeColor(_:))

        configureStyleControl()
        styleControl.target = self
        styleControl.action = #selector(changeStyle(_:))

        let save = NSButton(title: "Save", target: self, action: #selector(save))
        save.toolTip = "Save (S)"

        let controls = NSStackView(views: [
            toolControl, color, styleControl, NSView(), save,
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
        canvas.endTextEditing()
        return AnnotationRenderer.flattenedImage(
            source: model.sourceImage,
            annotations: model.annotations
        )
    }

    func handleEscape() {
        if !canvas.endTextEditing() {
            onFinish?()
        }
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
        canvas.endTextEditing()
        model.tool = tool
        if let index = AnnotationTool.allCases.firstIndex(of: tool) {
            toolControl.selectedSegment = index
        }
        configureStyleControl()
        canvas.updateCursor()
    }

    @objc private func changeTool(_ sender: NSSegmentedControl) {
        let tools = AnnotationTool.allCases
        guard tools.indices.contains(sender.selectedSegment) else { return }
        selectTool(tools[sender.selectedSegment])
    }

    @objc private func changeColor(_ sender: NSPopUpButton) {
        model.color = AnnotationColor(rawValue: sender.titleOfSelectedItem ?? "") ?? .red
        canvas.updateTextEditorStyle()
    }

    @objc private func changeStyle(_ sender: NSPopUpButton) {
        if model.tool == .text {
            model.textSize =
                AnnotationTextSize(rawValue: sender.titleOfSelectedItem ?? "") ?? .medium
            canvas.updateTextEditorStyle()
        } else {
            model.thickness =
                AnnotationThickness(rawValue: sender.titleOfSelectedItem ?? "") ?? .medium
        }
    }

    private func configureStyleControl() {
        styleControl.removeAllItems()
        if model.tool == .text {
            styleControl.addItems(withTitles: AnnotationTextSize.allCases.map(\.rawValue))
            styleControl.selectItem(withTitle: model.textSize.rawValue)
            styleControl.toolTip = "Text size"
        } else {
            styleControl.addItems(withTitles: AnnotationThickness.allCases.map(\.rawValue))
            styleControl.selectItem(withTitle: model.thickness.rawValue)
            styleControl.toolTip = "Line thickness"
        }
    }
}

private final class InlineTextView: NSTextView {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

private final class AnnotationCanvasView: NSView, NSTextViewDelegate {
    private let model: AnnotationEditorModel
    private var draft: AnnotationShape?
    private var textEditor: InlineTextView?
    private var textOrigin: CGPoint?
    private var textMaxWidth: CGFloat?

    var isEditingText: Bool { textEditor != nil }

    init(model: AnnotationEditorModel) {
        self.model = model
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        updateTextEditorGeometry()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: model.tool == .text ? .iBeam : .crosshair)
    }

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
        endTextEditing()
        guard let point = imagePoint(for: event) else { return }
        switch model.tool {
        case .pencil: draft = .pencil([point])
        case .rectangle: draft = .rectangle(start: point, end: point)
        case .arrow: draft = .arrow(start: point, end: point)
        case .text:
            beginTextEditing(at: point)
            return
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
        case .text:
            break
        }
        needsDisplay = true
    }

    func updateCursor() {
        window?.invalidateCursorRects(for: self)
    }

    func updateTextEditorStyle() {
        guard let textEditor else { return }
        textEditor.textColor = model.color.nsColor
        updateTextEditorGeometry()
    }

    @discardableResult
    func endTextEditing() -> Bool {
        guard let textEditor, let textOrigin, let textMaxWidth else { return false }
        let text = textEditor.string
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.commit(
                .text(
                    origin: textOrigin,
                    text: text,
                    maxWidth: textMaxWidth
                )
            )
        }
        textEditor.removeFromSuperview()
        self.textEditor = nil
        self.textOrigin = nil
        self.textMaxWidth = nil
        window?.makeFirstResponder(nil)
        needsDisplay = true
        return true
    }

    func textDidChange(_ notification: Notification) {
        resizeTextEditor()
    }

    private func beginTextEditing(at point: CGPoint) {
        let imageRect = AnnotationRenderer.aspectFitRect(
            imageSize: model.sourceImage.size,
            in: bounds
        )
        let displayScale = imageRect.width / max(model.sourceImage.size.width, 1)
        let origin = CGPoint(
            x: AnnotationTextLayout.adjustedOriginX(
                clickX: point.x,
                imageWidth: model.sourceImage.size.width,
                displayScale: displayScale
            ),
            y: point.y
        )
        let inset = CGSize(width: 3, height: 2)
        let editor = InlineTextView(
            frame: CGRect(origin: .zero, size: CGSize(width: 40, height: 40))
        )
        editor.delegate = self
        editor.textColor = model.color.nsColor
        editor.backgroundColor = .clear
        editor.drawsBackground = false
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = []
        editor.textContainerInset = inset
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.lineFragmentPadding = 0
        editor.onEscape = { [weak self] in
            self?.endTextEditing()
        }
        editor.wantsLayer = true
        editor.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.65).cgColor
        editor.layer?.borderWidth = 1
        editor.layer?.cornerRadius = 3

        addSubview(editor)
        textEditor = editor
        textOrigin = origin
        textMaxWidth = max(model.sourceImage.size.width - origin.x, 1)
        updateTextEditorGeometry()
        window?.makeFirstResponder(editor)
    }

    private func updateTextEditorGeometry() {
        guard let textEditor, let textOrigin, let textMaxWidth else { return }
        let imageRect = AnnotationRenderer.aspectFitRect(
            imageSize: model.sourceImage.size,
            in: bounds
        )
        let scale = imageRect.width / max(model.sourceImage.size.width, 1)
        let inset = textEditor.textContainerInset
        let viewPoint = CGPoint(
            x: imageRect.minX + textOrigin.x * scale,
            y: imageRect.minY + textOrigin.y * scale
        )
        textEditor.font = NSFont.systemFont(
            ofSize: model.textSize.points * scale,
            weight: .medium
        )
        textEditor.frame.origin = CGPoint(
            x: viewPoint.x - inset.width,
            y: viewPoint.y - inset.height
        )
        textEditor.frame.size.width = textMaxWidth * scale + inset.width * 2
        resizeTextEditor()
    }

    private func resizeTextEditor() {
        guard let textEditor, let layoutManager = textEditor.layoutManager,
              let textContainer = textEditor.textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        textEditor.frame.size.height = max(
            usedHeight + textEditor.textContainerInset.height * 2,
            (textEditor.font?.pointSize ?? 16) * 1.5 + 4
        )
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
