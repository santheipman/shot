import AppKit

typealias ScreenCaptureFunction = (
    _ rect: CGRect,
    _ completion: @escaping (Result<NSImage, Error>) -> Void
) -> Void

final class CaptureCoordinator {
    private let captureScreen: ScreenCaptureFunction
    private let makeEditor: EditorFactory
    private let makePin: PinFactory
    private let handleCaptureError: (Error) -> Void
    private let fullscreenRect: () -> CGRect?
    private var overlayController: SelectionOverlayController?
    private var editors: [Int: any EditorWindow] = [:]
    private var pins: [Int: any PinWindow] = [:]

    init(
        captureScreen: @escaping ScreenCaptureFunction = ScreenCapture.capture,
        makeEditor: @escaping EditorFactory = {
            PreviewWindowController(image: $0, captureRect: $1)
        },
        makePin: @escaping PinFactory = {
            PinWindowController(image: $0, captureRect: $1)
        },
        handleCaptureError: ((Error) -> Void)? = nil,
        fullscreenRect: @escaping () -> CGRect? = CaptureCoordinator.displayBoundsContainingMouse
    ) {
        self.captureScreen = captureScreen
        self.makeEditor = makeEditor
        self.makePin = makePin
        self.handleCaptureError = handleCaptureError ?? Self.presentCaptureError
        self.fullscreenRect = fullscreenRect
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
        guard overlayController == nil else { return }

        EventLog.shared.write("selection_started")
        let controller = SelectionOverlayController()
        overlayController = controller

        controller.begin { [weak self] result in
            guard let self else { return }
            self.overlayController = nil

            switch result {
            case .cancelled:
                EventLog.shared.write("selection_cancelled")
            case let .selected(rect):
                EventLog.shared.write("selection_completed rect=\(rect.debugDescription)")
                self.capture(rect: rect)
            }
        }
    }

    func beginPinAreaSelection() {
        guard overlayController == nil else { return }

        EventLog.shared.write("pin_selection_started")
        let controller = SelectionOverlayController()
        overlayController = controller

        controller.begin { [weak self] result in
            guard let self else { return }
            self.overlayController = nil

            switch result {
            case .cancelled:
                EventLog.shared.write("pin_selection_cancelled")
            case let .selected(rect):
                EventLog.shared.write("pin_selection_completed rect=\(rect.debugDescription)")
                self.capturePin(rect: rect)
            }
        }
    }

    func capture(rect: CGRect) {
        performCapture(rect: rect) { [weak self] image in
            self?.presentEditor(image: image, near: rect)
        }
    }

    func capturePin(rect: CGRect) {
        performCapture(rect: rect) { [weak self] image in
            self?.presentPin(image: image, near: rect)
        }
    }

    private func performCapture(
        rect: CGRect,
        onSuccess: @escaping (NSImage) -> Void
    ) {
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
                onSuccess(image)
            case let .failure(error):
                EventLog.shared.write("capture_failed error=\(error.localizedDescription)")
                self?.handleCaptureError(error)
            }
        }
    }

    func closeAllEditors() {
        EventLog.shared.write("close_all_editors count=\(editors.count)")
        for editor in Array(editors.values) {
            editor.close()
        }
    }

    private func presentEditor(image: NSImage, near captureRect: CGRect) {
        let editor = makeEditor(image, captureRect)
        editor.onClose = { [weak self] windowNumber in
            self?.editors.removeValue(forKey: windowNumber)
            EventLog.shared.write(
                "editor_destroyed window_id=\(windowNumber) remaining=\(self?.editors.count ?? 0)"
            )
        }

        editor.present()
        guard let windowNumber = editor.identifier else { return }
        editors[windowNumber] = editor
        EventLog.shared.write(
            "editor_created window_id=\(windowNumber) live_editors=\(editors.count)"
        )
    }

    private func presentPin(image: NSImage, near captureRect: CGRect) {
        let pin = makePin(image, captureRect)
        pin.onClose = { [weak self] windowNumber in
            self?.pins.removeValue(forKey: windowNumber)
            EventLog.shared.write(
                "pin_destroyed window_id=\(windowNumber) remaining=\(self?.pins.count ?? 0)"
            )
        }

        pin.present()
        guard let windowNumber = pin.identifier else { return }
        pins[windowNumber] = pin
        EventLog.shared.write(
            "pin_created window_id=\(windowNumber) live_pins=\(pins.count)"
        )
    }

    private static func presentCaptureError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "AeroShot couldn’t capture the screen"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func displayBoundsContainingMouse() -> CGRect? {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard
            let screen,
            let screenNumber = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber
        else {
            return nil
        }

        return CGDisplayBounds(CGDirectDisplayID(screenNumber.uint32Value)).integral
    }
}
