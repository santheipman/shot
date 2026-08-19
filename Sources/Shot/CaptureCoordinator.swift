import AppKit

typealias ScreenCaptureFunction = (
    _ rect: CGRect,
    _ completion: @escaping (Result<NSImage, Error>) -> Void
) -> Void

final class CaptureCoordinator {
    private let captureScreen: ScreenCaptureFunction
    private let makeEditor: ManagedWindowFactory
    private let makePin: ManagedWindowFactory
    private let makeOCRResult: ManagedWindowFactory
    private let handleCaptureError: (Error) -> Void
    private let fullscreenRect: () -> CGRect?
    private let keyboardSelectionEnabled: () -> Bool
    private var overlayController: SelectionOverlayController?
    private var editors: [Int: any ManagedWindow] = [:]
    private var pins: [Int: any ManagedWindow] = [:]
    private var ocrResults: [Int: any ManagedWindow] = [:]

    init(
        captureScreen: @escaping ScreenCaptureFunction = ScreenCapture.capture,
        makeEditor: @escaping ManagedWindowFactory = {
            PreviewWindowController(image: $0, captureRect: $1)
        },
        makePin: @escaping ManagedWindowFactory = {
            PinWindowController(image: $0, captureRect: $1)
        },
        makeOCRResult: @escaping ManagedWindowFactory = {
            OCRResultWindowController(image: $0, captureRect: $1)
        },
        handleCaptureError: ((Error) -> Void)? = nil,
        fullscreenRect: @escaping () -> CGRect? = CaptureCoordinator.displayBoundsContainingMouse,
        keyboardSelectionEnabled: @escaping () -> Bool = { Preferences.keyboardSelection }
    ) {
        self.captureScreen = captureScreen
        self.makeEditor = makeEditor
        self.makePin = makePin
        self.makeOCRResult = makeOCRResult
        self.handleCaptureError = handleCaptureError ?? Self.presentCaptureError
        self.fullscreenRect = fullscreenRect
        self.keyboardSelectionEnabled = keyboardSelectionEnabled
    }

    func captureFullscreen() {
        guard let rect = fullscreenRect() else {
            EventLog.shared.write("fullscreen_capture_failed reason=no_display")
            handleCaptureError(ScreenCaptureError.displayNotFound)
            return
        }

        EventLog.shared.write("fullscreen_capture_requested rect=\(rect.debugDescription)")
        capture(rect: rect)
    }

    func beginAreaSelection() {
        beginSelection(logPrefix: "selection") {
            $0.presentEditor(image: $1, near: $2)
        }
    }

    func beginPinAreaSelection() {
        beginSelection(logPrefix: "pin_selection") {
            $0.presentPin(image: $1, near: $2)
        }
    }

    func beginTextAreaSelection() {
        beginSelection(logPrefix: "ocr_selection") {
            $0.presentOCRResult(image: $1, near: $2)
        }
    }

    func capture(rect: CGRect) {
        EventLog.shared.write("capture_started rect=\(rect.debugDescription)")

        captureScreen(rect) { [weak self] result in
            switch result {
            case let .success(image):
                if EventLog.shared.isFileLoggingEnabled {
                    let diagnostics = ImageDiagnostics.measure(image)
                    EventLog.shared.write(
                        "capture_completed pixels=\(Int(image.size.width))x\(Int(image.size.height)) " +
                            "mean_rgb=\(String(format: "%.2f", diagnostics.meanRGB)) " +
                            "dark_fraction=\(String(format: "%.4f", diagnostics.darkFraction))"
                    )
                }
                self?.presentEditor(image: image, near: rect)
            case let .failure(error):
                EventLog.shared.write("capture_failed error=\(error.localizedDescription)")
                self?.handleCaptureError(error)
            }
        }
    }

    private func beginSelection(
        logPrefix: String,
        present: @escaping (CaptureCoordinator, NSImage, CGRect) -> Void
    ) {
        guard overlayController == nil else { return }

        EventLog.shared.write("\(logPrefix)_started")
        let controller = SelectionOverlayController(
            keyboardEnabled: keyboardSelectionEnabled()
        )
        overlayController = controller

        controller.begin { [weak self] result in
            guard let self else { return }
            self.overlayController = nil

            switch result {
            case .cancelled:
                EventLog.shared.write("\(logPrefix)_cancelled")
            case let .selected(rect, image):
                EventLog.shared.write("\(logPrefix)_completed rect=\(rect.debugDescription)")
                present(self, image, rect)
            case let .failed(error):
                EventLog.shared.write("\(logPrefix)_failed error=\(error.localizedDescription)")
                self.handleCaptureError(error)
            }
        }
    }

    private func presentEditor(image: NSImage, near captureRect: CGRect) {
        present(
            makeEditor(image, captureRect),
            in: \.editors,
            name: "editor",
            liveCountKey: "live_editors"
        )
    }

    func presentPin(image: NSImage, near captureRect: CGRect) {
        present(
            makePin(image, captureRect),
            in: \.pins,
            name: "pin",
            liveCountKey: "live_pins"
        )
    }

    func presentOCRResult(image: NSImage, near captureRect: CGRect) {
        present(
            makeOCRResult(image, captureRect),
            in: \.ocrResults,
            name: "ocr_window",
            liveCountKey: "live_windows"
        )
    }

    private func present(
        _ window: any ManagedWindow,
        in storage: ReferenceWritableKeyPath<CaptureCoordinator, [Int: any ManagedWindow]>,
        name: String,
        liveCountKey: String
    ) {
        window.onClose = { [weak self] windowNumber in
            self?[keyPath: storage].removeValue(forKey: windowNumber)
            EventLog.shared.write(
                "\(name)_destroyed window_id=\(windowNumber) remaining=\(self?[keyPath: storage].count ?? 0)"
            )
        }

        window.present()
        guard let windowNumber = window.identifier else { return }
        self[keyPath: storage][windowNumber] = window
        EventLog.shared.write(
            "\(name)_created window_id=\(windowNumber) \(liveCountKey)=\(self[keyPath: storage].count)"
        )
    }

    private static func presentCaptureError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Shot couldn’t capture the screen"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func displayBoundsContainingMouse() -> CGRect? {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let displayID = screen?.displayID else { return nil }
        return CGDisplayBounds(displayID).integral
    }
}
