import AppKit

typealias TextRecognitionFunction = (
    _ image: NSImage,
    _ completion: @escaping (Result<String, Error>) -> Void
) -> Void

final class OCRResultWindowController: ManagedWindowController {
    init(
        image: NSImage,
        captureRect: CGRect,
        recognizeText: @escaping TextRecognitionFunction = TextRecognizer.recognize
    ) {
        let panel = OCRPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Shot — Capture Text"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isRestorable = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.minSize = NSSize(width: 480, height: 420)

        super.init(window: panel)
        panel.delegate = self
        let resultViewController = OCRResultViewController(
            image: image,
            recognizeText: recognizeText
        )
        panel.onCopySelection = { [weak resultViewController] in
            resultViewController?.copySelection() ?? false
        }
        panel.contentViewController = resultViewController
        sizeAndPosition(panel: panel, captureRect: captureRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func sizeAndPosition(panel: NSPanel, captureRect: CGRect) {
        let visibleFrame = Self.visibleFrame(nearQuartzPoint: captureRect.origin)
        let size = CGSize(
            width: min(720, visibleFrame.width * 0.8),
            height: min(640, visibleFrame.height * 0.8)
        )
        panel.setContentSize(size)
        centerWindow(in: visibleFrame)
    }
}

private final class OCRPanel: NSPanel {
    var onCopySelection: (() -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isCopyShortcut(event), onCopySelection?() == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.isEscapeKey {
            close()
            return
        }
        super.keyDown(with: event)
    }

    private func isCopyShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == "c"
    }
}

private final class OCRResultViewController: NSViewController {
    private let image: NSImage
    private let recognizeText: TextRecognitionFunction
    private let textView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "Recognizing text…")
    private let copyButton = NSButton(title: "Copy Text", target: nil, action: nil)

    init(image: NSImage, recognizeText: @escaping TextRecognitionFunction) {
        self.image = image
        self.recognizeText = recognizeText
        super.init(nibName: nil, bundle: nil)
        copyButton.target = self
        copyButton.action = #selector(copyText)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(imageView)

        textView.isEditable = false
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.frame = CGRect(x: 0, y: 0, width: 600, height: 200)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 600,
            height: CGFloat.greatestFiniteMagnitude
        )

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        root.addSubview(scrollView)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .secondaryLabelColor
        root.addSubview(statusLabel)

        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.isEnabled = false
        root.addSubview(copyButton)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            imageView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            imageView.heightAnchor.constraint(equalTo: root.heightAnchor, multiplier: 0.42),

            scrollView.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -12),

            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            statusLabel.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor),

            copyButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            copyButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            copyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
        ])

        view = root
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        recognizeText(image) { [weak self] result in
            self?.show(result)
        }
    }

    private func show(_ result: Result<String, Error>) {
        switch result {
        case let .success(text):
            textView.string = text
            textView.isEditable = true
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                statusLabel.stringValue = "No text found"
                copyButton.isEnabled = false
                EventLog.shared.write("ocr_completed text_found=false")
            } else {
                statusLabel.stringValue = ""
                copyButton.isEnabled = true
                EventLog.shared.write("ocr_completed text_found=true")
            }
        case let .failure(error):
            statusLabel.stringValue = "Text recognition failed: \(error.localizedDescription)"
            copyButton.isEnabled = false
            EventLog.shared.write("ocr_failed error=\(error.localizedDescription)")
        }
    }

    func copySelection() -> Bool {
        let range = textView.selectedRange()
        guard range.length > 0 else { return false }
        let selectedText = (textView.string as NSString).substring(with: range)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(selectedText, forType: .string) else { return false }
        EventLog.shared.write("ocr_selected_text_copied")
        return true
    }

    @objc private func copyText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(textView.string, forType: .string) else {
            statusLabel.stringValue = "Shot couldn’t copy the recognized text."
            return
        }
        statusLabel.stringValue = "Copied"
        EventLog.shared.write("ocr_text_copied")
    }
}
