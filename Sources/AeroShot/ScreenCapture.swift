import AppKit

enum ScreenCaptureError: LocalizedError, Equatable {
    case invalidRectangle
    case displayNotFound
    case permissionRequired
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .invalidRectangle:
            return "The selected area is empty."
        case .displayNotFound:
            return "AeroShot couldn’t find the display containing the pointer."
        case .permissionRequired:
            return "Allow AeroShot in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch it."
        case .captureFailed:
            return "macOS did not return an image for the selected area."
        }
    }
}

enum ScreenCapture {
    static func capture(
        rect: CGRect,
        completion: @escaping (Result<NSImage, Error>) -> Void
    ) {
        let integralRect = rect.integral
        guard integralRect.width >= 2, integralRect.height >= 2 else {
            completion(.failure(ScreenCaptureError.invalidRectangle))
            return
        }

        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            completion(.failure(ScreenCaptureError.permissionRequired))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            guard let cgImage = CGWindowListCreateImage(
                integralRect,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.bestResolution, .boundsIgnoreFraming]
            ) else {
                DispatchQueue.main.async {
                    completion(.failure(ScreenCaptureError.captureFailed))
                }
                return
            }

            let image = NSImage(
                cgImage: cgImage,
                size: NSSize(
                    width: integralRect.width,
                    height: integralRect.height
                )
            )
            DispatchQueue.main.async {
                completion(.success(image))
            }
        }
    }
}
