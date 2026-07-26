import AppKit

struct ImageDiagnostics {
    let meanRGB: Double
    let darkFraction: Double

    static func measure(_ image: NSImage) -> ImageDiagnostics {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let source = image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else {
            return ImageDiagnostics(meanRGB: 0, darkFraction: 1)
        }

        let width = 32
        let height = 32
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard
            let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return ImageDiagnostics(meanRGB: 0, darkFraction: 1)
        }

        context.interpolationQuality = .low
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        var total = 0.0
        var darkPixels = 0
        let pixelCount = width * height

        for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let red = Double(pixels[offset])
            let green = Double(pixels[offset + 1])
            let blue = Double(pixels[offset + 2])
            let mean = (red + green + blue) / 3
            total += mean
            if mean < 5 {
                darkPixels += 1
            }
        }

        return ImageDiagnostics(
            meanRGB: total / Double(pixelCount),
            darkFraction: Double(darkPixels) / Double(pixelCount)
        )
    }
}
