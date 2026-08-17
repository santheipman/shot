import AppKit

protocol ManagedWindow: AnyObject {
    var identifier: Int? { get }
    var onClose: ((Int) -> Void)? { get set }

    func present()
}

typealias ManagedWindowFactory = (_ image: NSImage, _ captureRect: CGRect) -> any ManagedWindow

class ManagedWindowController: NSWindowController, NSWindowDelegate, ManagedWindow {
    var onClose: ((Int) -> Void)?
    var identifier: Int? { window?.windowNumber }

    func present() {
        guard let window else { return }
        // Mark the newly created window as key before activating Shot.
        // AppKit then brings forward this key window rather than an older
        // window that belongs to another workspace.
        window.makeKeyAndOrderFront(nil)
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
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

    static func visibleFrame(nearQuartzPoint point: CGPoint) -> CGRect {
        let screen = NSScreen.containingQuartzPoint(point) ?? NSScreen.main
        return screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
    }

    func centerWindow(in visibleFrame: CGRect) {
        guard let window else { return }
        window.setFrameOrigin(
            CGPoint(
                x: visibleFrame.midX - window.frame.width / 2,
                y: visibleFrame.midY - window.frame.height / 2
            )
        )
    }
}
