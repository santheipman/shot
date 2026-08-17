import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let shortcutSetupCompletedKey = "shortcutSetupCompleted"

    private struct CaptureAction {
        let title: String
        let key: String
        let keyCode: UInt32
        let hotKeyName: String
        let run: (CaptureCoordinator) -> Void
    }

    private static let captureActions: [CaptureAction] = [
        CaptureAction(
            title: "Capture Text Area",
            key: "1",
            keyCode: UInt32(kVK_ANSI_1),
            hotKeyName: "command-shift-1",
            run: { $0.beginTextAreaSelection() }
        ),
        CaptureAction(
            title: "Capture Full Screen",
            key: "3",
            keyCode: UInt32(kVK_ANSI_3),
            hotKeyName: "command-shift-3",
            run: { $0.captureFullscreen() }
        ),
        CaptureAction(
            title: "Capture Area",
            key: "4",
            keyCode: UInt32(kVK_ANSI_4),
            hotKeyName: "command-shift-4",
            run: { $0.beginAreaSelection() }
        ),
        CaptureAction(
            title: "Pin Area",
            key: "2",
            keyCode: UInt32(kVK_ANSI_2),
            hotKeyName: "command-shift-2",
            run: { $0.beginPinAreaSelection() }
        ),
    ]

    private let captureCoordinator = CaptureCoordinator()
    private var statusItem: NSStatusItem?
    private var hotKeys: GlobalHotKey?
    private var shortcutSetupWindowController: ShortcutSetupWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        configureStatusItem()

        hotKeys = GlobalHotKey(shortcuts: Self.captureActions.map { action in
            .init(
                name: action.hotKeyName,
                keyCode: action.keyCode,
                modifiers: UInt32(cmdKey | shiftKey)
            ) { [weak self] in
                guard let self else { return }
                action.run(self.captureCoordinator)
            }
        })

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
        for (index, action) in Self.captureActions.enumerated() {
            let menuItem = NSMenuItem(
                title: action.title,
                action: #selector(runCaptureAction(_:)),
                keyEquivalent: action.key
            )
            menuItem.keyEquivalentModifierMask = [.command, .shift]
            menuItem.target = self
            menuItem.tag = index
            menu.addItem(menuItem)
        }
        menu.addItem(NSMenuItem.separator())

        let shortcutSetupItem = NSMenuItem(
            title: "Shortcut Setup…",
            action: #selector(showShortcutSetup),
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

    @objc private func runCaptureAction(_ sender: NSMenuItem) {
        guard Self.captureActions.indices.contains(sender.tag) else { return }
        Self.captureActions[sender.tag].run(captureCoordinator)
    }

    @objc private func showShortcutSetup() {
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
