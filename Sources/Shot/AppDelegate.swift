import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let shortcutSetupCompletedKey = "shortcutSetupCompleted"

    private let captureCoordinator = CaptureCoordinator()
    private var statusItem: NSStatusItem?
    private var hotKeys: GlobalHotKey?
    private var shortcutSetupWindowController: ShortcutSetupWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        configureStatusItem()

        let modifiers = UInt32(cmdKey | shiftKey)
        hotKeys = GlobalHotKey(shortcuts: [
            .init(
                name: "command-shift-1",
                keyCode: UInt32(kVK_ANSI_1),
                modifiers: modifiers
            ) { [weak self] in
                self?.captureCoordinator.beginTextAreaSelection()
            },
            .init(
                name: "command-shift-3",
                keyCode: UInt32(kVK_ANSI_3),
                modifiers: modifiers
            ) { [weak self] in
                self?.captureCoordinator.captureFullscreen()
            },
            .init(
                name: "command-shift-4",
                keyCode: UInt32(kVK_ANSI_4),
                modifiers: modifiers
            ) { [weak self] in
                self?.captureCoordinator.beginAreaSelection()
            },
            .init(
                name: "command-shift-2",
                keyCode: UInt32(kVK_ANSI_2),
                modifiers: modifiers
            ) { [weak self] in
                self?.captureCoordinator.beginPinAreaSelection()
            },
        ])

        EventLog.shared.write("app_started pid=\(ProcessInfo.processInfo.processIdentifier)")
        EventLog.shared.write(
            "screen_capture_permission granted=\(CGPreflightScreenCaptureAccess())"
        )

        if !UserDefaults.standard.bool(forKey: Self.shortcutSetupCompletedKey) {
            DispatchQueue.main.async { [weak self] in
                self?.showShortcutSetup()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        EventLog.shared.write("app_terminated")
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "viewfinder",
                accessibilityDescription: "Shot"
            )
        }

        let menu = NSMenu()
        addCaptureMenuItem(
            to: menu,
            title: "Capture Text Area",
            action: #selector(captureTextArea),
            key: "1"
        )
        addCaptureMenuItem(
            to: menu,
            title: "Capture Full Screen",
            action: #selector(captureFullscreen),
            key: "3"
        )
        addCaptureMenuItem(
            to: menu,
            title: "Capture Area",
            action: #selector(captureArea),
            key: "4"
        )
        addCaptureMenuItem(
            to: menu,
            title: "Pin Area",
            action: #selector(capturePinnedArea),
            key: "2"
        )
        menu.addItem(NSMenuItem.separator())

        let shortcutSetupItem = NSMenuItem(
            title: "Shortcut Setup…",
            action: #selector(openShortcutSetup),
            keyEquivalent: ""
        )
        shortcutSetupItem.target = self
        menu.addItem(shortcutSetupItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Shot",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    private func addCaptureMenuItem(
        to menu: NSMenu,
        title: String,
        action: Selector,
        key: String
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.command, .shift]
        item.target = self
        menu.addItem(item)
    }

    @objc private func captureFullscreen() {
        captureCoordinator.captureFullscreen()
    }

    @objc private func captureTextArea() {
        captureCoordinator.beginTextAreaSelection()
    }

    @objc private func captureArea() {
        captureCoordinator.beginAreaSelection()
    }

    @objc private func capturePinnedArea() {
        captureCoordinator.beginPinAreaSelection()
    }

    @objc private func openShortcutSetup() {
        showShortcutSetup()
    }

    private func showShortcutSetup() {
        if let shortcutSetupWindowController {
            shortcutSetupWindowController.present()
            return
        }

        let controller = ShortcutSetupWindowController()
        controller.onDone = {
            UserDefaults.standard.set(true, forKey: Self.shortcutSetupCompletedKey)
        }
        controller.onClose = { [weak self, weak controller] in
            guard self?.shortcutSetupWindowController === controller else { return }
            self?.shortcutSetupWindowController = nil
        }
        shortcutSetupWindowController = controller
        controller.present()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
