import AppKit

final class ShortcutSetupWindowController: NSWindowController, NSWindowDelegate {
    var onDone: (() -> Void)?
    var onClose: (() -> Void)?

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 190),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Set Up Shot Shortcuts"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        super.init(window: panel)
        panel.delegate = self
        panel.contentView = makeContentView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    private func makeContentView() -> NSView {
        let title = NSTextField(labelWithString: "Disable macOS screenshot shortcuts")
        title.font = .boldSystemFont(ofSize: 18)

        let instructions = NSTextField(wrappingLabelWithString: """
        Shot uses ⇧⌘3 and ⇧⌘4.

        Open Keyboard Shortcuts, select Screenshots, and turn both off.
        """)

        let openSettingsButton = NSButton(
            title: "Open Keyboard Shortcuts",
            target: self,
            action: #selector(openKeyboardSettings)
        )
        openSettingsButton.bezelStyle = .rounded
        openSettingsButton.keyEquivalent = "\r"

        let doneButton = NSButton(
            title: "Done",
            target: self,
            action: #selector(finishSetup)
        )
        doneButton.bezelStyle = .rounded

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [openSettingsButton, spacer, doneButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        let content = NSStackView(views: [title, instructions, buttons])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        buttons.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        let container = NSView()
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            content.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -24),
        ])
        return container
    }

    @objc private func openKeyboardSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func finishSetup() {
        onDone?()
        close()
    }
}
