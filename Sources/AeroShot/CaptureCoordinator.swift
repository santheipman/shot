import AppKit

typealias ScreenCaptureFunction = (
    _ rect: CGRect,
    _ completion: @escaping (Result<NSImage, Error>) -> Void
) -> Void

final class CaptureCoordinator {
    private let captureScreen: ScreenCaptureFunction
    private let makeEditor: EditorFactory
    private let handleCaptureError: (Error) -> Void
    private var overlayController: SelectionOverlayController?
    private var editors: [Int: any EditorWindow] = [:]

    init(
        captureScreen: @escaping ScreenCaptureFunction = ScreenCapture.capture,
        makeEditor: @escaping EditorFactory = {
            PreviewWindowController(image: $0, captureRect: $1)
        },
        handleCaptureError: ((Error) -> Void)? = nil
    ) {
        self.captureScreen = captureScreen
        self.makeEditor = makeEditor
        self.handleCaptureError = handleCaptureError ?? Self.presentCaptureError
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

    private static func presentCaptureError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "AeroShot couldn’t capture the screen"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
