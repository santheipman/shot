import AppKit

protocol PinWindow: AnyObject {
    var identifier: Int? { get }
    var onClose: ((Int) -> Void)? { get set }

    func present()
    func close()
}

typealias PinFactory = (_ image: NSImage, _ captureRect: CGRect) -> any PinWindow
