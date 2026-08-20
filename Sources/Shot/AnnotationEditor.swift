import AppKit

enum AnnotationTool: String, CaseIterable {
    case select = "Select"
    case pencil = "Pencil"
    case rectangle = "Rectangle"
    case arrow = "Arrow"
    case text = "Text"
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
        case "v": return .selectTool(.select)
        case "r": return .selectTool(.rectangle)
        case "p": return .selectTool(.pencil)
        case "a": return .selectTool(.arrow)
        case "t": return .selectTool(.text)
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

struct AnnotationStyle: Equatable {
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

struct Annotation: Equatable, Identifiable {
    let id: UUID
    let shape: AnnotationShape
    let style: AnnotationStyle

    init(id: UUID = UUID(), shape: AnnotationShape, style: AnnotationStyle) {
        self.id = id
        self.shape = shape
        self.style = style
    }
}

final class AnnotationEditorModel {
    let sourceImage: NSImage
    private(set) var annotations: [Annotation] = []
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []
    var tool: AnnotationTool = .rectangle
    var color: AnnotationColor = .red
    var thickness: AnnotationThickness = .medium
    var textSize: AnnotationTextSize = .medium

    init(sourceImage: NSImage) {
        self.sourceImage = sourceImage
    }

    func commit(_ shape: AnnotationShape) {
        recordUndoSnapshot()
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
    }

    @discardableResult
    func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(annotations)
        annotations = previous
        return true
    }

    @discardableResult
    func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(annotations)
        annotations = next
        return true
    }

    func annotation(id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    @discardableResult
    func replace(_ annotation: Annotation) -> Bool {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }),
              annotations[index] != annotation else { return false }
        recordUndoSnapshot()
        annotations[index] = annotation
        return true
    }

    @discardableResult
    func remove(id: UUID) -> Bool {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else {
            return false
        }
        recordUndoSnapshot()
        annotations.remove(at: index)
        return true
    }

    private func recordUndoSnapshot() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }
}

enum AnnotationGeometry {
    static func bounds(of annotation: Annotation) -> CGRect {
        switch annotation.shape {
        case let .pencil(points):
            guard let first = points.first else { return .zero }
            return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
                $0.union(CGRect(origin: $1, size: .zero))
            }
        case let .rectangle(start, end):
            return rect(from: start, to: end)
        case let .arrow(start, end):
            return ([start, end] + arrowHeadPoints(
                start: start,
                end: end,
                thickness: annotation.style.thickness.points
            )).reduce(CGRect.null) { partial, point in
                partial.union(CGRect(origin: point, size: .zero))
            }
        case let .text(origin, text, maxWidth):
            let font = NSFont.systemFont(
                ofSize: annotation.style.textSize.points,
                weight: .medium
            )
            let attributedText = NSAttributedString(
                string: text,
                attributes: [.font: font]
            )
            let size = attributedText.boundingRect(
                with: CGSize(width: maxWidth, height: 100_000),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).integral.size
            return CGRect(origin: origin, size: size)
        }
    }

    static func contains(
        _ point: CGPoint,
        annotation: Annotation,
        tolerance: CGFloat
    ) -> Bool {
        switch annotation.shape {
        case let .pencil(points):
            return polylineContains(point, points: points, tolerance: tolerance)
        case let .rectangle(start, end):
            let rectangle = rect(from: start, to: end)
            let corners = [
                CGPoint(x: rectangle.minX, y: rectangle.minY),
                CGPoint(x: rectangle.maxX, y: rectangle.minY),
                CGPoint(x: rectangle.maxX, y: rectangle.maxY),
                CGPoint(x: rectangle.minX, y: rectangle.maxY),
            ]
            return zip(corners, corners.dropFirst() + [corners[0]]).contains {
                distance(from: point, toSegmentFrom: $0, to: $1) <= tolerance
            }
        case let .arrow(start, end):
            let head = arrowHeadPoints(
                start: start,
                end: end,
                thickness: annotation.style.thickness.points
            )
            return distance(from: point, toSegmentFrom: start, to: end) <= tolerance
                || head.contains {
                    distance(from: point, toSegmentFrom: end, to: $0) <= tolerance
                }
        case .text:
            return bounds(of: annotation).insetBy(dx: -tolerance, dy: -tolerance)
                .contains(point)
        }
    }

    static func translated(_ annotation: Annotation, by delta: CGPoint) -> Annotation {
        let shape: AnnotationShape
        switch annotation.shape {
        case let .pencil(points):
            shape = .pencil(points.map { $0 + delta })
        case let .rectangle(start, end):
            shape = .rectangle(start: start + delta, end: end + delta)
        case let .arrow(start, end):
            shape = .arrow(start: start + delta, end: end + delta)
        case let .text(origin, text, maxWidth):
            shape = .text(origin: origin + delta, text: text, maxWidth: maxWidth)
        }
        return Annotation(id: annotation.id, shape: shape, style: annotation.style)
    }

    static func constrainedTranslation(
        of annotation: Annotation,
        proposed delta: CGPoint,
        imageSize: CGSize
    ) -> CGPoint {
        let annotationBounds = bounds(of: annotation)
        guard !annotationBounds.isNull else { return .zero }
        let minimumX = min(0, -annotationBounds.minX)
        let maximumX = max(0, imageSize.width - annotationBounds.maxX)
        let minimumY = min(0, -annotationBounds.minY)
        let maximumY = max(0, imageSize.height - annotationBounds.maxY)
        return CGPoint(
            x: clamped(delta.x, lower: minimumX, upper: maximumX),
            y: clamped(delta.y, lower: minimumY, upper: maximumY)
        )
    }

    private static func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else { return 0 }
        return min(max(value, lower), upper)
    }

    private static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private static func arrowHeadPoints(
        start: CGPoint,
        end: CGPoint,
        thickness: CGFloat
    ) -> [CGPoint] {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(thickness * 4, 12)
        let spread: CGFloat = .pi / 7
        return [
            CGPoint(
                x: end.x - headLength * cos(angle - spread),
                y: end.y - headLength * sin(angle - spread)
            ),
            CGPoint(
                x: end.x - headLength * cos(angle + spread),
                y: end.y - headLength * sin(angle + spread)
            ),
        ]
    }

    private static func polylineContains(
        _ point: CGPoint,
        points: [CGPoint],
        tolerance: CGFloat
    ) -> Bool {
        guard let first = points.first else { return false }
        if points.count == 1 {
            return hypot(point.x - first.x, point.y - first.y) <= tolerance
        }
        return zip(points, points.dropFirst()).contains {
            distance(from: point, toSegmentFrom: $0, to: $1) <= tolerance
        }
    }

    private static func distance(
        from point: CGPoint,
        toSegmentFrom start: CGPoint,
        to end: CGPoint
    ) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let projection = min(
            max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0),
            1
        )
        let closest = CGPoint(x: start.x + projection * dx, y: start.y + projection * dy)
        return hypot(point.x - closest.x, point.y - closest.y)
    }
}

private extension CGPoint {
    static func + (left: CGPoint, right: CGPoint) -> CGPoint {
        CGPoint(x: left.x + right.x, y: left.y + right.y)
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
