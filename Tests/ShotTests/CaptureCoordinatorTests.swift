import AppKit
import Testing
@testable import Shot

@Suite
struct CaptureCoordinatorTests {
    @Test
    func successfulCaptureCreatesAndPresentsOneEditor() {
        let image = NSImage(size: NSSize(width: 20, height: 10))
        let factory = FakeWindowFactory()
        let coordinator = makeCoordinator(image: image, factory: factory)

        coordinator.capture(rect: CGRect(x: 10, y: 20, width: 30, height: 40))

        #expect(factory.windows.count == 1)
        #expect(factory.windows[0].presentCallCount == 1)
        #expect(factory.images[0] === image)
        #expect(factory.captureRects[0] == CGRect(x: 10, y: 20, width: 30, height: 40))
    }

    @Test
    func eachCaptureCreatesANewEditorWithoutPresentingAnExistingEditorAgain() {
        let factory = FakeWindowFactory()
        let coordinator = makeCoordinator(factory: factory)

        coordinator.capture(rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        coordinator.capture(rect: CGRect(x: 20, y: 20, width: 10, height: 10))

        #expect(factory.windows.count == 2)
        #expect(factory.windows[0] !== factory.windows[1])
        #expect(factory.windows[0].presentCallCount == 1)
        #expect(factory.windows[1].presentCallCount == 1)
    }

    @Test
    func closingOneEditorDoesNotCloseOrPresentAnotherEditor() {
        let factory = FakeWindowFactory()
        let coordinator = makeCoordinator(factory: factory)
        coordinator.capture(rect: .zero)
        coordinator.capture(rect: .zero)

        factory.windows[0].close()

        #expect(factory.windows[0].closeCallCount == 1)
        #expect(factory.windows[1].closeCallCount == 0)
        #expect(factory.windows[1].presentCallCount == 1)
    }

    @Test
    func captureFailureCreatesNoEditorAndReportsTheError() {
        let expectedError = TestError.captureFailed
        let factory = FakeWindowFactory()
        var reportedError: Error?
        let coordinator = CaptureCoordinator(
            captureScreen: { _, completion in completion(.failure(expectedError)) },
            makeEditor: factory.make,
            handleCaptureError: { reportedError = $0 }
        )

        coordinator.capture(rect: .zero)

        #expect(factory.windows.isEmpty)
        #expect(reportedError as? TestError == expectedError)
    }

    @Test
    func fullscreenCaptureUsesResolvedDisplayBoundsAndOpensEditor() {
        let expectedRect = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let factory = FakeWindowFactory()
        var capturedRect: CGRect?
        let coordinator = CaptureCoordinator(
            captureScreen: { rect, completion in
                capturedRect = rect
                completion(.success(NSImage(size: rect.size)))
            },
            makeEditor: factory.make,
            handleCaptureError: { _ in Issue.record("Unexpected capture error") },
            fullscreenRect: { expectedRect }
        )

        coordinator.captureFullscreen()

        #expect(capturedRect == expectedRect)
        #expect(factory.captureRects == [expectedRect])
        #expect(factory.windows.count == 1)
        #expect(factory.windows[0].presentCallCount == 1)
    }

    @Test
    func fullscreenCaptureWithoutDisplayReportsErrorAndDoesNotCapture() {
        let factory = FakeWindowFactory()
        var captureCalled = false
        var reportedError: Error?
        let coordinator = CaptureCoordinator(
            captureScreen: { _, _ in captureCalled = true },
            makeEditor: factory.make,
            handleCaptureError: { reportedError = $0 },
            fullscreenRect: { nil }
        )

        coordinator.captureFullscreen()

        #expect(!captureCalled)
        #expect(factory.windows.isEmpty)
        #expect(reportedError as? ScreenCaptureError == .displayNotFound)
    }

    @Test
    func pinPresentationCreatesAndPresentsPinWithoutCreatingEditor() {
        let image = NSImage(size: NSSize(width: 40, height: 20))
        let editorFactory = FakeWindowFactory()
        let pinFactory = FakeWindowFactory(firstIdentifier: 100)
        let rect = CGRect(x: 10, y: 20, width: 40, height: 20)
        let coordinator = CaptureCoordinator(
            makeEditor: editorFactory.make,
            makePin: pinFactory.make,
            handleCaptureError: { _ in Issue.record("Unexpected capture error") }
        )

        coordinator.presentPin(image: image, near: rect)

        #expect(editorFactory.windows.isEmpty)
        #expect(pinFactory.windows.count == 1)
        #expect(pinFactory.windows[0].presentCallCount == 1)
        #expect(pinFactory.images[0] === image)
        #expect(pinFactory.captureRects == [rect])
    }

    @Test
    func pinsCoexistAndCloseIndependently() {
        let pinFactory = FakeWindowFactory(firstIdentifier: 100)
        let coordinator = CaptureCoordinator(makePin: pinFactory.make)

        coordinator.presentPin(
            image: NSImage(size: NSSize(width: 20, height: 10)),
            near: .zero
        )
        coordinator.presentPin(
            image: NSImage(size: NSSize(width: 20, height: 10)),
            near: .zero
        )
        pinFactory.windows[0].close()

        #expect(pinFactory.windows.count == 2)
        #expect(pinFactory.windows[0].closeCallCount == 1)
        #expect(pinFactory.windows[1].closeCallCount == 0)
        #expect(pinFactory.windows[1].presentCallCount == 1)
    }

    @Test
    func textCaptureResultCreatesASeparateWindow() {
        let image = NSImage(size: NSSize(width: 40, height: 20))
        let editorFactory = FakeWindowFactory()
        let resultFactory = FakeWindowFactory(firstIdentifier: 200)
        let rect = CGRect(x: 10, y: 20, width: 40, height: 20)
        let coordinator = CaptureCoordinator(
            makeEditor: editorFactory.make,
            makeOCRResult: resultFactory.make
        )

        coordinator.presentOCRResult(image: image, near: rect)

        #expect(editorFactory.windows.isEmpty)
        #expect(resultFactory.windows.count == 1)
        #expect(resultFactory.windows[0].presentCallCount == 1)
        #expect(resultFactory.images[0] === image)
        #expect(resultFactory.captureRects == [rect])
    }

    @Test
    func textCaptureResultWindowsCloseIndependently() {
        let resultFactory = FakeWindowFactory(firstIdentifier: 200)
        let coordinator = CaptureCoordinator(makeOCRResult: resultFactory.make)

        coordinator.presentOCRResult(image: NSImage(size: NSSize(width: 10, height: 10)), near: .zero)
        coordinator.presentOCRResult(image: NSImage(size: NSSize(width: 10, height: 10)), near: .zero)
        resultFactory.windows[0].close()

        #expect(resultFactory.windows.count == 2)
        #expect(resultFactory.windows[0].closeCallCount == 1)
        #expect(resultFactory.windows[1].closeCallCount == 0)
        #expect(resultFactory.windows[1].presentCallCount == 1)
    }

    private func makeCoordinator(
        image: NSImage = NSImage(size: NSSize(width: 10, height: 10)),
        factory: FakeWindowFactory
    ) -> CaptureCoordinator {
        CaptureCoordinator(
            captureScreen: { _, completion in completion(.success(image)) },
            makeEditor: factory.make,
            handleCaptureError: { _ in
                Issue.record("Unexpected capture error")
            }
        )
    }
}

private final class FakeWindowFactory {
    private var nextIdentifier: Int
    private(set) var windows: [FakeWindow] = []
    private(set) var images: [NSImage] = []
    private(set) var captureRects: [CGRect] = []

    init(firstIdentifier: Int = 1) {
        nextIdentifier = firstIdentifier
    }

    func make(image: NSImage, captureRect: CGRect) -> any ManagedWindow {
        let window = FakeWindow(identifier: nextIdentifier)
        nextIdentifier += 1
        windows.append(window)
        images.append(image)
        captureRects.append(captureRect)
        return window
    }
}

private final class FakeWindow: ManagedWindow {
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
