import AppKit

enum AnnotationTool: String, CaseIterable {
    case pencil = "Pencil"
    case rectangle = "Rectangle"
    case arrow = "Arrow"
}

enum EditorShortcut: Equatable {
    case save
    case selectTool(AnnotationTool)

    static func resolve(
        characters: String?,
        modifiers: NSEvent.ModifierFlags
    ) -> EditorShortcut? {
        let unsupportedModifiers = modifiers
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .control, .option])
        guard unsupportedModifiers.isEmpty else { return nil }

        switch characters?.lowercased() {
        case "s": return .save
        case "r": return .selectTool(.rectangle)
        case "p": return .selectTool(.pencil)
        case "a": return .selectTool(.arrow)
        default: return nil
        }
    }
}

enum AnnotationColor: String, CaseIterable {
    case red = "Red"
    case yellow = "Yellow"
    case green = "Green"
    case blue = "Blue"
    case black = "Black"
    case white = "White"

    var nsColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .black: return .black
        case .white: return .white
        }
    }
}

enum AnnotationThickness: String, CaseIterable {
    case thin = "Thin"
    case medium = "Medium"
    case thick = "Thick"

    var points: CGFloat {
        switch self {
        case .thin: return 2
        case .medium: return 5
        case .thick: return 9
        }
    }
}

struct AnnotationStyle {
    var color: AnnotationColor
    var thickness: AnnotationThickness
}

enum AnnotationShape {
    case pencil([CGPoint])
    case rectangle(start: CGPoint, end: CGPoint)
    case arrow(start: CGPoint, end: CGPoint)
}

struct Annotation {
    let shape: AnnotationShape
    let style: AnnotationStyle
}

final class AnnotationEditorModel {
    let sourceImage: NSImage
    private(set) var annotations: [Annotation] = []
    var tool: AnnotationTool = .pencil
    var color: AnnotationColor = .red
    var thickness: AnnotationThickness = .medium

    init(sourceImage: NSImage) {
        self.sourceImage = sourceImage
    }

    func commit(_ shape: AnnotationShape) {
        annotations.append(
            Annotation(
                shape: shape,
                style: AnnotationStyle(color: color, thickness: thickness)
            )
        )
    }

    @discardableResult
    func undo() -> Bool {
        guard !annotations.isEmpty else { return false }
        annotations.removeLast()
        return true
    }
}

enum ScreenshotFileNamer {
    static func availableURL(
        in directory: URL,
        timestamp: String,
        fileExists: (URL) -> Bool = {
            FileManager.default.fileExists(atPath: $0.path)
        }
    ) -> URL {
        var number = 1
        while true {
            let suffix = number == 1 ? "" : " \(number)"
            let url = directory.appendingPathComponent(
                "AeroShot \(timestamp)\(suffix).png"
            )
            if !fileExists(url) {
                return url
            }
            number += 1
        }
    }
}

enum AnnotationRenderer {
    static func aspectFitRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    static func imagePoint(from viewPoint: CGPoint, imageRect: CGRect, imageSize: CGSize) -> CGPoint? {
        guard imageRect.contains(viewPoint), imageRect.width > 0, imageRect.height > 0 else {
            return nil
        }
        return CGPoint(
            x: (viewPoint.x - imageRect.minX) * imageSize.width / imageRect.width,
            y: (viewPoint.y - imageRect.minY) * imageSize.height / imageRect.height
        )
    }

    static func clampedImagePoint(
        from viewPoint: CGPoint,
        imageRect: CGRect,
        imageSize: CGSize
    ) -> CGPoint? {
        guard imageRect.width > 0, imageRect.height > 0 else { return nil }
        let clampedPoint = CGPoint(
            x: min(max(viewPoint.x, imageRect.minX), imageRect.maxX),
            y: min(max(viewPoint.y, imageRect.minY), imageRect.maxY)
        )
        return CGPoint(
            x: (clampedPoint.x - imageRect.minX) * imageSize.width / imageRect.width,
            y: (clampedPoint.y - imageRect.minY) * imageSize.height / imageRect.height
        )
    }

    static func draw(
        annotations: [Annotation],
        in context: CGContext,
        imageSize: CGSize,
        destinationRect: CGRect
    ) {
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        context.saveGState()
        context.translateBy(x: destinationRect.minX, y: destinationRect.minY)
        context.scaleBy(
            x: destinationRect.width / imageSize.width,
            y: destinationRect.height / imageSize.height
        )
        for annotation in annotations {
            draw(annotation, in: context)
        }
        context.restoreGState()
    }

    static func flattenedImage(source: NSImage, annotations: [Annotation]) -> NSImage? {
        guard let sourceCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        // Start from a direct pixel copy. Drawing NSImage into a point-sized
        // bitmap context applies the backing scale a second time.
        let bitmap = NSBitmapImageRep(cgImage: sourceCG)
        bitmap.size = source.size
        guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        // Draw in source points. NSGraphicsContext applies the bitmap's backing
        // scale, mapping annotations to native pixels exactly once.
        draw(
            annotations: annotations,
            in: graphics.cgContext,
            imageSize: source.size,
            destinationRect: CGRect(origin: .zero, size: source.size)
        )
        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: source.size)
        result.addRepresentation(bitmap)
        return result
    }

    private static func draw(_ annotation: Annotation, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(annotation.style.color.nsColor.cgColor)
        context.setLineWidth(annotation.style.thickness.points)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.shape {
        case let .pencil(points):
            guard let first = points.first else { break }
            context.beginPath()
            context.move(to: first)
            for point in points.dropFirst() {
                context.addLine(to: point)
            }
            if points.count == 1 {
                context.addLine(to: CGPoint(x: first.x + 0.01, y: first.y))
            }
            context.strokePath()
        case let .rectangle(start, end):
            context.stroke(
                CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                )
            )
        case let .arrow(start, end):
            context.beginPath()
            context.move(to: start)
            context.addLine(to: end)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength = max(annotation.style.thickness.points * 4, 12)
            let spread: CGFloat = .pi / 7
            context.move(to: end)
            context.addLine(
                to: CGPoint(
                    x: end.x - headLength * cos(angle - spread),
                    y: end.y - headLength * sin(angle - spread)
                )
            )
            context.move(to: end)
            context.addLine(
                to: CGPoint(
                    x: end.x - headLength * cos(angle + spread),
                    y: end.y - headLength * sin(angle + spread)
                )
            )
            context.strokePath()
        }
        context.restoreGState()
    }
}
