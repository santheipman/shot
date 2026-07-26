import AppKit
import Testing
@testable import AeroShot

@Suite
struct CaptureCoordinatorTests {
    @Test
    func successfulCaptureCreatesAndPresentsOneEditor() {
        let image = NSImage(size: NSSize(width: 20, height: 10))
        let factory = FakeEditorFactory()
        let coordinator = makeCoordinator(image: image, factory: factory)

        coordinator.capture(rect: CGRect(x: 10, y: 20, width: 30, height: 40))

        #expect(factory.editors.count == 1)
        #expect(factory.editors[0].presentCallCount == 1)
        #expect(factory.images[0] === image)
        #expect(factory.captureRects[0] == CGRect(x: 10, y: 20, width: 30, height: 40))
    }

    @Test
    func eachCaptureCreatesANewEditorWithoutPresentingAnExistingEditorAgain() {
        let factory = FakeEditorFactory()
        let coordinator = makeCoordinator(factory: factory)

        coordinator.capture(rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        coordinator.capture(rect: CGRect(x: 20, y: 20, width: 10, height: 10))

        #expect(factory.editors.count == 2)
        #expect(factory.editors[0] !== factory.editors[1])
        #expect(factory.editors[0].presentCallCount == 1)
        #expect(factory.editors[1].presentCallCount == 1)
    }

    @Test
    func closingOneEditorDoesNotCloseOrPresentAnotherEditor() {
        let factory = FakeEditorFactory()
        let coordinator = makeCoordinator(factory: factory)
        coordinator.capture(rect: .zero)
        coordinator.capture(rect: .zero)

        factory.editors[0].close()

        #expect(factory.editors[0].closeCallCount == 1)
        #expect(factory.editors[1].closeCallCount == 0)
        #expect(factory.editors[1].presentCallCount == 1)

        coordinator.closeAllEditors()

        #expect(factory.editors[0].closeCallCount == 1)
        #expect(factory.editors[1].closeCallCount == 1)
    }

    @Test
    func closeAllEditorsClosesEveryLiveEditor() {
        let factory = FakeEditorFactory()
        let coordinator = makeCoordinator(factory: factory)
        coordinator.capture(rect: .zero)
        coordinator.capture(rect: .zero)

        coordinator.closeAllEditors()

        #expect(factory.editors.map(\.closeCallCount) == [1, 1])
    }

    @Test
    func captureFailureCreatesNoEditorAndReportsTheError() {
        let expectedError = TestError.captureFailed
        let factory = FakeEditorFactory()
        var reportedError: Error?
        let coordinator = CaptureCoordinator(
            captureScreen: { _, completion in completion(.failure(expectedError)) },
            makeEditor: factory.makeEditor,
            handleCaptureError: { reportedError = $0 }
        )

        coordinator.capture(rect: .zero)

        #expect(factory.editors.isEmpty)
        #expect(reportedError as? TestError == expectedError)
    }

    @Test
    func fullscreenCaptureUsesResolvedDisplayBoundsAndOpensEditor() {
        let expectedRect = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let factory = FakeEditorFactory()
        var capturedRect: CGRect?
        let coordinator = CaptureCoordinator(
            captureScreen: { rect, completion in
                capturedRect = rect
                completion(.success(NSImage(size: rect.size)))
            },
            makeEditor: factory.makeEditor,
            handleCaptureError: { _ in Issue.record("Unexpected capture error") },
            fullscreenRect: { expectedRect }
        )

        coordinator.captureFullscreen()

        #expect(capturedRect == expectedRect)
        #expect(factory.captureRects == [expectedRect])
        #expect(factory.editors.count == 1)
        #expect(factory.editors[0].presentCallCount == 1)
    }

    @Test
    func fullscreenCaptureWithoutDisplayReportsErrorAndDoesNotCapture() {
        let factory = FakeEditorFactory()
        var captureCalled = false
        var reportedError: Error?
        let coordinator = CaptureCoordinator(
            captureScreen: { _, _ in captureCalled = true },
            makeEditor: factory.makeEditor,
            handleCaptureError: { reportedError = $0 },
            fullscreenRect: { nil }
        )

        coordinator.captureFullscreen()

        #expect(!captureCalled)
        #expect(factory.editors.isEmpty)
        #expect(reportedError as? ScreenCaptureError == .displayNotFound)
    }

    @Test
    func pinCaptureCreatesAndPresentsPinWithoutCreatingEditor() {
        let image = NSImage(size: NSSize(width: 40, height: 20))
        let editorFactory = FakeEditorFactory()
        let pinFactory = FakePinFactory()
        let rect = CGRect(x: 10, y: 20, width: 40, height: 20)
        let coordinator = CaptureCoordinator(
            captureScreen: { _, completion in completion(.success(image)) },
            makeEditor: editorFactory.makeEditor,
            makePin: pinFactory.makePin,
            handleCaptureError: { _ in Issue.record("Unexpected capture error") }
        )

        coordinator.capturePin(rect: rect)

        #expect(editorFactory.editors.isEmpty)
        #expect(pinFactory.pins.count == 1)
        #expect(pinFactory.pins[0].presentCallCount == 1)
        #expect(pinFactory.images[0] === image)
        #expect(pinFactory.captureRects == [rect])
    }

    @Test
    func pinsCoexistAndCloseIndependently() {
        let editorFactory = FakeEditorFactory()
        let pinFactory = FakePinFactory()
        let coordinator = CaptureCoordinator(
            captureScreen: { _, completion in
                completion(.success(NSImage(size: NSSize(width: 20, height: 10))))
            },
            makeEditor: editorFactory.makeEditor,
            makePin: pinFactory.makePin,
            handleCaptureError: { _ in Issue.record("Unexpected capture error") }
        )

        coordinator.capturePin(rect: .zero)
        coordinator.capturePin(rect: .zero)
        pinFactory.pins[0].close()

        #expect(pinFactory.pins.count == 2)
        #expect(pinFactory.pins[0].closeCallCount == 1)
        #expect(pinFactory.pins[1].closeCallCount == 0)
        #expect(pinFactory.pins[1].presentCallCount == 1)
    }

    @Test
    func failedPinCaptureCreatesNeitherPinNorEditorAndReportsError() {
        let expectedError = TestError.captureFailed
        let editorFactory = FakeEditorFactory()
        let pinFactory = FakePinFactory()
        var reportedError: Error?
        let coordinator = CaptureCoordinator(
            captureScreen: { _, completion in completion(.failure(expectedError)) },
            makeEditor: editorFactory.makeEditor,
            makePin: pinFactory.makePin,
            handleCaptureError: { reportedError = $0 }
        )

        coordinator.capturePin(rect: .zero)

        #expect(editorFactory.editors.isEmpty)
        #expect(pinFactory.pins.isEmpty)
        #expect(reportedError as? TestError == expectedError)
    }

    private func makeCoordinator(
        image: NSImage = NSImage(size: NSSize(width: 10, height: 10)),
        factory: FakeEditorFactory
    ) -> CaptureCoordinator {
        CaptureCoordinator(
            captureScreen: { _, completion in completion(.success(image)) },
            makeEditor: factory.makeEditor,
            handleCaptureError: { _ in
                Issue.record("Unexpected capture error")
            }
        )
    }
}

private final class FakeEditorFactory {
    private var nextIdentifier = 1
    private(set) var editors: [FakeEditorWindow] = []
    private(set) var images: [NSImage] = []
    private(set) var captureRects: [CGRect] = []

    func makeEditor(image: NSImage, captureRect: CGRect) -> any EditorWindow {
        let editor = FakeEditorWindow(identifier: nextIdentifier)
        nextIdentifier += 1
        editors.append(editor)
        images.append(image)
        captureRects.append(captureRect)
        return editor
    }
}

private final class FakeEditorWindow: EditorWindow {
    let identifier: Int?
    var onClose: ((Int) -> Void)?
    private(set) var presentCallCount = 0
    private(set) var closeCallCount = 0

    init(identifier: Int) {
        self.identifier = identifier
    }

    func present() {
        presentCallCount += 1
    }

    func close() {
        guard closeCallCount == 0, let identifier else { return }
        closeCallCount += 1
        onClose?(identifier)
    }
}

private final class FakePinFactory {
    private var nextIdentifier = 100
    private(set) var pins: [FakePinWindow] = []
    private(set) var images: [NSImage] = []
    private(set) var captureRects: [CGRect] = []

    func makePin(image: NSImage, captureRect: CGRect) -> any PinWindow {
        let pin = FakePinWindow(identifier: nextIdentifier)
        nextIdentifier += 1
        pins.append(pin)
        images.append(image)
        captureRects.append(captureRect)
        return pin
    }
}

private final class FakePinWindow: PinWindow {
    let identifier: Int?
    var onClose: ((Int) -> Void)?
    private(set) var presentCallCount = 0
    private(set) var closeCallCount = 0

    init(identifier: Int) {
        self.identifier = identifier
    }

    func present() {
        presentCallCount += 1
    }

    func close() {
        guard closeCallCount == 0, let identifier else { return }
        closeCallCount += 1
        onClose?(identifier)
    }
}

private enum TestError: Error {
    case captureFailed
}
