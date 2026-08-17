import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard
            let number = deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber
        else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    static func containingQuartzPoint(_ point: CGPoint) -> NSScreen? {
        screens.first { screen in
            guard let displayID = screen.displayID else { return false }
            return CGDisplayBounds(displayID).contains(point)
        }
    }
}

extension NSEvent {
    var isEscapeKey: Bool { keyCode == 53 } // kVK_Escape
}
