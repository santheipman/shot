import Carbon

final class GlobalHotKey {
    struct Shortcut {
        let name: String
        let keyCode: UInt32
        let modifiers: UInt32
        let handler: () -> Void
    }

    private static let signature = OSType(
        UInt32(ascii: "A") << 24 |
            UInt32(ascii: "E") << 16 |
            UInt32(ascii: "R") << 8 |
            UInt32(ascii: "O")
    )

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var handlers: [UInt32: () -> Void] = [:]

    init(shortcuts: [Shortcut]) {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard
                    status == noErr,
                    hotKeyID.signature == GlobalHotKey.signature
                else {
                    return OSStatus(eventNotHandledErr)
                }

                let owner = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                guard let handler = owner.handlers[hotKeyID.id] else {
                    return OSStatus(eventNotHandledErr)
                }

                DispatchQueue.main.async(execute: handler)
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            EventLog.shared.write("hotkey_handler_install_failed status=\(installStatus)")
            return
        }

        for (index, shortcut) in shortcuts.enumerated() {
            register(shortcut, id: UInt32(index + 1))
        }
    }

    deinit {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func register(_ shortcut: Shortcut, id: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            EventLog.shared.write(
                "hotkey_register_failed name=\(shortcut.name) status=\(status)"
            )
            return
        }

        hotKeyRefs.append(hotKeyRef)
        handlers[id] = shortcut.handler
        EventLog.shared.write("hotkey_registered name=\(shortcut.name)")
    }
}

private extension UInt32 {
    init(ascii character: Character) {
        self = character.asciiValue.map(UInt32.init) ?? 0
    }
}
