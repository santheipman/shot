import AppKit

enum AnnotationTool: String, CaseIterable {
    case pencil = "Pencil"
    case rectangle = "Rectangle"
    case arrow = "Arrow"
    case text = "Text"

    /// The shape this tool draws between two image points. Text is placed
    /// rather than dragged, so it has no two-point shape.
    func shape(from start: CGPoint, to end: CGPoint) -> AnnotationShape? {
        switch self {
        case .pencil: return .pencil([start, end])
        case .rectangle: return .rectangle(start: start, end: end)
        case .arrow: return .arrow(start: start, end: end)
        case .text: return nil
        }
    }
}

enum EditorShortcut: Equatable {
    case save
    case copy
    case undo
    case redo
    case selectTool(AnnotationTool)
    case selectColor(AnnotationColor)
    /// Thinner or thicker line, or smaller or larger text for the text tool.
    case adjustStyle(by: Int)
    case toggleHelp

    static func resolve(
        characters: String?,
        modifiers: NSEvent.ModifierFlags
    ) -> EditorShortcut? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        guard flags.intersection([.control, .option]).isEmpty else { return nil }
        guard let character = characters?.lowercased() else { return nil }

        if flags.contains(.command) {
            switch character {
            case "s": return .save
            case "c": return .copy
            case "z": return flags.contains(.shift) ? .redo : .undo
            default: return nil
            }
        }

        switch character {
        case "s": return .save
        case "r": return .selectTool(.rectangle)
        case "p": return .selectTool(.pencil)
        case "a": return .selectTool(.arrow)
        case "t": return .selectTool(.text)
        case "[": return .adjustStyle(by: -1)
        case "]": return .adjustStyle(by: 1)
        case "?": return .toggleHelp
        default:
            guard
                let number = Int(character),
                let color = AnnotationColor.numbered(number)
            else { return nil }
            return .selectColor(color)
        }
    }
}

extension CaseIterable where Self: Equatable {
    /// The neighbouring case, clamped at both ends of `allCases`.
    func stepped(by delta: Int) -> Self {
        let cases = Array(Self.allCases)
        guard let index = cases.firstIndex(of: self) else { return self }
        return cases[min(max(index + delta, 0), cases.count - 1)]
    }
}

enum AnnotationColor: String, CaseIterable {
    case red = "Red"
    case yellow = "Yellow"
    case green = "Green"
    case blue = "Blue"
    case black = "Black"
    case white = "White"

    /// The toolbar order, which the 1-6 shortcuts follow.
    static func numbered(_ number: Int) -> AnnotationColor? {
        let cases = Array(allCases)
        guard cases.indices.contains(number - 1) else { return nil }
        return cases[number - 1]
    }

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

enum AnnotationTextSize: String, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    var points: CGFloat {
        switch self {
        case .small: return 16
        case .medium: return 24
        case .large: return 36
        }
    }
}

enum AnnotationTextLayout {
    static let minimumViewWidth: CGFloat = 40

    static func adjustedOriginX(
        clickX: CGFloat,
        imageWidth: CGFloat,
        displayScale: CGFloat
    ) -> CGFloat {
        guard imageWidth > 0, displayScale > 0 else { return 0 }
        let minimumImageWidth = min(minimumViewWidth / displayScale, imageWidth)
        return min(max(clickX, 0), imageWidth - minimumImageWidth)
    }
}

struct AnnotationStyle {
    var color: AnnotationColor
    var thickness: AnnotationThickness
    var textSize: AnnotationTextSize = .medium
}

enum AnnotationShape: Equatable {
    case pencil([CGPoint])
    case rectangle(start: CGPoint, end: CGPoint)
    case arrow(start: CGPoint, end: CGPoint)
    case text(origin: CGPoint, text: String, maxWidth: CGFloat)
}

struct Annotation {
    let shape: AnnotationShape
    let style: AnnotationStyle
}

final class AnnotationEditorModel {
    let sourceImage: NSImage
    private(set) var annotations: [Annotation] = []
    private var undone: [Annotation] = []
    var tool: AnnotationTool = .pencil
    var color: AnnotationColor = .red
    var thickness: AnnotationThickness = .medium
    var textSize: AnnotationTextSize = .medium

    init(sourceImage: NSImage) {
        self.sourceImage = sourceImage
    }

    func commit(_ shape: AnnotationShape) {
        annotations.append(
            Annotation(
                shape: shape,
                style: AnnotationStyle(
                    color: color,
                    thickness: thickness,
                    textSize: textSize
                )
            )
        )
        undone.removeAll()
    }

    @discardableResult
    func undo() -> Bool {
        guard let annotation = annotations.popLast() else { return false }
        undone.append(annotation)
        return true
    }

    @discardableResult
    func redo() -> Bool {
        guard let annotation = undone.popLast() else { return false }
        annotations.append(annotation)
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
                "Shot \(timestamp)\(suffix).png"
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
        return mapToImage(viewPoint, imageRect: imageRect, imageSize: imageSize)
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
        return mapToImage(clampedPoint, imageRect: imageRect, imageSize: imageSize)
    }

    private static func mapToImage(_ point: CGPoint, imageRect: CGRect, imageSize: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x - imageRect.minX) * imageSize.width / imageRect.width,
            y: (point.y - imageRect.minY) * imageSize.height / imageRect.height
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
        // The editor canvas is flipped and stores points from the image's
        // top-left. Bitmap contexts use a bottom-left origin, so match the
        // canvas before drawing the annotations.
        graphics.cgContext.translateBy(x: 0, y: source.size.height)
        graphics.cgContext.scaleBy(x: 1, y: -1)
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
        case let .text(origin, text, maxWidth):
            let font = NSFont.systemFont(
                ofSize: annotation.style.textSize.points,
                weight: .medium
            )
            let attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: annotation.style.color.nsColor,
                ]
            )
            let options: NSString.DrawingOptions = [
                .usesLineFragmentOrigin,
                .usesFontLeading,
            ]
            let textHeight = ceil(
                attributedText.boundingRect(
                    with: CGSize(width: maxWidth, height: 100_000),
                    options: options
                ).height
            )
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(
                cgContext: context,
                flipped: true
            )
            attributedText.draw(
                with: CGRect(
                    x: origin.x,
                    y: origin.y,
                    width: maxWidth,
                    height: textHeight
                ),
                options: options
            )
            NSGraphicsContext.restoreGraphicsState()
        }
        context.restoreGState()
    }
}
