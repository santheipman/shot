import Foundation

enum Preferences {
    static let keyboardSelectionKey = "keyboardSelection"

    /// Draw the capture area with vim keys instead of the mouse.
    /// Toggle from the status menu or with
    /// `defaults write dev.sanvq.shot keyboardSelection -bool true`.
    static var keyboardSelection: Bool {
        get { UserDefaults.standard.bool(forKey: keyboardSelectionKey) }
        set { UserDefaults.standard.set(newValue, forKey: keyboardSelectionKey) }
    }
}
