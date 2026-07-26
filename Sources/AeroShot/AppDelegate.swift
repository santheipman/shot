import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let captureCoordinator = CaptureCoordinator()
    private var statusItem: NSStatusItem?
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        configureStatusItem()

        hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_4),
            modifiers: UInt32(controlKey | shiftKey)
        ) { [weak self] in
            self?.captureCoordinator.beginAreaSelection()
        }

        EventLog.shared.write("app_started pid=\(ProcessInfo.processInfo.processIdentifier)")
        EventLog.shared.write(
            "screen_capture_permission granted=\(CGPreflightScreenCaptureAccess())"
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        EventLog.shared.write("app_terminated")
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "viewfinder",
                accessibilityDescription: "AeroShot"
            )
        }

        let menu = NSMenu()
        let captureItem = NSMenuItem(
            title: "Capture Area",
            action: #selector(captureArea),
            keyEquivalent: ""
        )
        captureItem.target = self
        menu.addItem(captureItem)
        menu.addItem(NSMenuItem.separator())

        let shortcutItem = NSMenuItem(
            title: "Shortcut: Control–Shift–4",
            action: nil,
            keyEquivalent: ""
        )
        shortcutItem.isEnabled = false
        menu.addItem(shortcutItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit AeroShot",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func captureArea() {
        captureCoordinator.beginAreaSelection()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
