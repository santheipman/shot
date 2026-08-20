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
        panel.onRedo = { [weak editor] in editor?.redo() }
        panel.onDelete = { [weak editor] in editor?.deleteSelection() }
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
    var onRedo: (() -> Void)?
    var onDelete: (() -> Void)?
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
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.charactersIgnoringModifiers?.lowercased() == "z" {
            if modifiers == .command {
                onUndo?()
                return
            }
            if modifiers == [.command, .shift] {
                onRedo?()
                return
            }
        }
        if modifiers.isEmpty, (event.keyCode == 51 || event.keyCode == 117) {
            onDelete?()
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
    private let deleteButton: NSButton
    var onFinish: (() -> Void)?
    var onSave: (() -> Void)?
    var isEditingText: Bool { canvas.isEditingText }

    init(model: AnnotationEditorModel) {
        self.model = model
        canvas = AnnotationCanvasView(model: model)
        styleControl = NSPopUpButton()
        let toolImages = [
            NSImage(systemSymbolName: "arrow.up.left", accessibilityDescription: "Select"),
            NSImage(systemSymbolName: "pencil", accessibilityDescription: "Pencil"),
            NSImage(systemSymbolName: "rectangle", accessibilityDescription: "Rectangle"),
            NSImage(systemSymbolName: "line.diagonal", accessibilityDescription: "Line"),
            Self.dashedLineToolImage(),
            NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: "Arrow"),
            NSImage(systemSymbolName: "textformat", accessibilityDescription: "Text"),
        ].compactMap { $0 }
        toolControl = NSSegmentedControl(
            images: toolImages,
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        deleteButton = NSButton(
            image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")!,
            target: nil,
            action: nil
        )
        super.init(nibName: nil, bundle: nil)
        toolControl.target = self
        toolControl.action = #selector(changeTool(_:))
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelection)
        canvas.onSelectionChanged = { [weak self] hasSelection in
            self?.deleteButton.isEnabled = hasSelection
        }
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

        toolControl.selectedSegment = AnnotationTool.allCases.firstIndex(of: model.tool) ?? 0
        toolControl.segmentStyle = .texturedRounded
        toolControl.setAccessibilityLabel("Annotation tool")
        toolControl.setToolTip("Select (V)", forSegment: 0)
        toolControl.setToolTip("Pencil (P)", forSegment: 1)
        toolControl.setToolTip("Rectangle (R)", forSegment: 2)
        toolControl.setToolTip("Line (L)", forSegment: 3)
        toolControl.setToolTip("Dashed Line (D)", forSegment: 4)
        toolControl.setToolTip("Arrow (A)", forSegment: 5)
        toolControl.setToolTip("Text (T)", forSegment: 6)

        deleteButton.bezelStyle = .texturedRounded
        deleteButton.toolTip = "Delete selected annotation (Delete)"
        deleteButton.isEnabled = false

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
            toolControl, color, styleControl, deleteButton, NSView(), save,
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
        if !canvas.endTextEditing(), !canvas.clearSelection() {
            onFinish?()
        }
    }

    @objc func undo() {
        if model.undo() {
            canvas.historyDidChange()
        }
    }

    @objc func redo() {
        if model.redo() {
            canvas.historyDidChange()
        }
    }

    @objc func deleteSelection() {
        canvas.deleteSelection()
    }

    @objc func save() {
        onSave?()
    }

    func selectTool(_ tool: AnnotationTool) {
        canvas.endTextEditing()
        model.tool = tool
        canvas.toolDidChange()
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

    private static func dashedLineToolImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.labelColor.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            let dash: [CGFloat] = [3, 2]
            dash.withUnsafeBufferPointer {
                path.setLineDash($0.baseAddress, count: $0.count, phase: 0)
            }
            path.move(to: NSPoint(x: 3, y: 3))
            path.line(to: NSPoint(x: 15, y: 15))
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Dashed Line"
        return image
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
    private var selectedAnnotationID: UUID? {
        didSet {
            guard oldValue != selectedAnnotationID else { return }
            onSelectionChanged?(selectedAnnotationID != nil)
        }
    }
    private var dragOrigin: CGPoint?
    private var draggedAnnotation: Annotation?
    private var moveDraft: Annotation?

    var isEditingText: Bool { textEditor != nil }
    var onSelectionChanged: ((Bool) -> Void)?

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
        let cursor: NSCursor
        switch model.tool {
        case .select: cursor = .arrow
        case .text: cursor = .iBeam
        default: cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
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
        var annotations = model.annotations.map { annotation in
            if let moveDraft, annotation.id == moveDraft.id {
                return moveDraft
            }
            return annotation
        }
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
        if let selected = selectedAnnotationForDisplay() {
            drawSelection(around: selected, imageRect: imageRect, context: context)
        }
    }

    override func mouseDown(with event: NSEvent) {
        endTextEditing()
        guard let point = imagePoint(for: event) else { return }
        switch model.tool {
        case .select:
            selectedAnnotationID = annotation(at: point)?.id
            if let selectedAnnotationID,
               let annotation = model.annotation(id: selectedAnnotationID) {
                dragOrigin = point
                draggedAnnotation = annotation
                moveDraft = annotation
            } else {
                endMove()
            }
            needsDisplay = true
            return
        case .pencil: draft = .pencil([point])
        case .rectangle: draft = .rectangle(start: point, end: point)
        case .line: draft = .line(start: point, end: point)
        case .dashedLine: draft = .dashedLine(start: point, end: point)
        case .arrow: draft = .arrow(start: point, end: point)
        case .text:
            beginTextEditing(at: point)
            return
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let point = imagePoint(for: event, clamped: true) else { return }
        if model.tool == .select {
            updateMove(with: point)
            return
        }
        updateDraft(with: point)
    }

    override func mouseUp(with event: NSEvent) {
        if model.tool == .select {
            if let point = imagePoint(for: event, clamped: true) {
                updateMove(with: point)
            }
            if let moveDraft {
                model.replace(moveDraft)
            }
            endMove()
            needsDisplay = true
            return
        }
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
        case let .line(start, _):
            self.draft = .line(start: start, end: point)
        case let .dashedLine(start, _):
            self.draft = .dashedLine(start: start, end: point)
        case let .arrow(start, _):
            self.draft = .arrow(start: start, end: point)
        case .text:
            break
        }
        needsDisplay = true
    }

    private func annotation(at point: CGPoint) -> Annotation? {
        let imageRect = AnnotationRenderer.aspectFitRect(
            imageSize: model.sourceImage.size,
            in: bounds
        )
        let scale = imageRect.width / max(model.sourceImage.size.width, 1)
        let tolerance = 8 / max(scale, 0.001)
        return model.annotations.reversed().first {
            AnnotationGeometry.contains(point, annotation: $0, tolerance: tolerance)
        }
    }

    private func updateMove(with point: CGPoint) {
        guard let dragOrigin, let draggedAnnotation else { return }
        let proposed = CGPoint(x: point.x - dragOrigin.x, y: point.y - dragOrigin.y)
        let delta = AnnotationGeometry.constrainedTranslation(
            of: draggedAnnotation,
            proposed: proposed,
            imageSize: model.sourceImage.size
        )
        moveDraft = AnnotationGeometry.translated(draggedAnnotation, by: delta)
        needsDisplay = true
    }

    private func endMove() {
        dragOrigin = nil
        draggedAnnotation = nil
        moveDraft = nil
    }

    private func selectedAnnotationForDisplay() -> Annotation? {
        if let moveDraft { return moveDraft }
        guard let selectedAnnotationID else { return nil }
        return model.annotation(id: selectedAnnotationID)
    }

    private func drawSelection(
        around annotation: Annotation,
        imageRect: CGRect,
        context: CGContext
    ) {
        let scale = imageRect.width / max(model.sourceImage.size.width, 1)
        let annotationBounds = AnnotationGeometry.bounds(of: annotation)
        var displayBounds = CGRect(
            x: imageRect.minX + annotationBounds.minX * scale,
            y: imageRect.minY + annotationBounds.minY * scale,
            width: annotationBounds.width * scale,
            height: annotationBounds.height * scale
        ).insetBy(dx: -4, dy: -4)
        displayBounds = displayBounds.intersection(bounds)
        guard !displayBounds.isNull else { return }
        context.saveGState()
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [4, 3])
        context.stroke(displayBounds)
        context.restoreGState()
    }

    func updateCursor() {
        window?.invalidateCursorRects(for: self)
    }

    func toolDidChange() {
        clearSelection()
        endMove()
        updateCursor()
        needsDisplay = true
    }

    @discardableResult
    func clearSelection() -> Bool {
        guard selectedAnnotationID != nil else { return false }
        selectedAnnotationID = nil
        endMove()
        needsDisplay = true
        return true
    }

    func deleteSelection() {
        guard let selectedAnnotationID, model.remove(id: selectedAnnotationID) else {
            return
        }
        self.selectedAnnotationID = nil
        endMove()
        needsDisplay = true
    }

    func historyDidChange() {
        if let selectedAnnotationID, model.annotation(id: selectedAnnotationID) == nil {
            self.selectedAnnotationID = nil
        }
        endMove()
        needsDisplay = true
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
