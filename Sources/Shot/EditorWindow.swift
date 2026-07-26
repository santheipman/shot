import AppKit

protocol EditorWindow: AnyObject {
    var identifier: Int? { get }
    var onClose: ((Int) -> Void)? { get set }

    func present()
    func close()
}

typealias EditorFactory = (_ image: NSImage, _ captureRect: CGRect) -> any EditorWindow
