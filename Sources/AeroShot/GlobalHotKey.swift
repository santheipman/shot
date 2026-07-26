import Carbon

final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let handler: () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

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

                guard status == noErr, hotKeyID.id == 1 else { return status }
                let owner = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    owner.handler()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            EventLog.shared.write("hotkey_install_failed status=\(installStatus)")
            return nil
        }

        let signature = OSType(
            UInt32(ascii: "A") << 24 |
                UInt32(ascii: "E") << 16 |
                UInt32(ascii: "R") << 8 |
                UInt32(ascii: "O")
        )
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            EventLog.shared.write("hotkey_register_failed status=\(registerStatus)")
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
            }
            return nil
        }

        EventLog.shared.write("hotkey_registered control-shift-4")
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}

private extension UInt32 {
    init(ascii character: Character) {
        self = character.asciiValue.map(UInt32.init) ?? 0
    }
}
