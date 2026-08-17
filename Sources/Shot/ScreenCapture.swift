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
            return "Shot couldn’t find the display containing the pointer."
        case .permissionRequired:
            return "Allow Shot in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch it."
        case .captureFailed:
            return "macOS did not return an image for the selected area."
        }
    }
}

enum ScreenCapture {
    static func snapshot(of screen: NSScreen) throws -> ScreenSnapshot {
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            throw ScreenCaptureError.permissionRequired
        }

        guard let displayID = screen.displayID else {
            throw ScreenCaptureError.displayNotFound
        }

        let displayBounds = CGDisplayBounds(displayID).integral
        guard let cgImage = CGWindowListCreateImage(
            displayBounds,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            throw ScreenCaptureError.captureFailed
        }

        return ScreenSnapshot(displayBounds: displayBounds, cgImage: cgImage)
    }

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

struct ScreenSnapshot {
    let displayBounds: CGRect
    let cgImage: CGImage

    var image: NSImage {
        NSImage(cgImage: cgImage, size: displayBounds.size)
    }

    func crop(to rect: CGRect) -> NSImage? {
        let clippedRect = rect.intersection(displayBounds).integral
        guard clippedRect.width >= 2, clippedRect.height >= 2 else {
            return nil
        }

        let scaleX = CGFloat(cgImage.width) / displayBounds.width
        let scaleY = CGFloat(cgImage.height) / displayBounds.height
        let pixelRect = CGRect(
            x: (clippedRect.minX - displayBounds.minX) * scaleX,
            y: (clippedRect.minY - displayBounds.minY) * scaleY,
            width: clippedRect.width * scaleX,
            height: clippedRect.height * scaleY
        ).integral

        guard let croppedImage = cgImage.cropping(to: pixelRect) else {
            return nil
        }
        return NSImage(cgImage: croppedImage, size: clippedRect.size)
    }
}
