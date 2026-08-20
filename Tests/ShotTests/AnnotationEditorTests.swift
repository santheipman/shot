import AppKit
import Testing
@testable import Shot

@Suite("Annotation editor")
struct AnnotationEditorTests {
    @Test(
        arguments: [
            ("s", EditorShortcut.save),
            ("v", EditorShortcut.selectTool(.select)),
            ("r", EditorShortcut.selectTool(.rectangle)),
            ("p", EditorShortcut.selectTool(.pencil)),
            ("a", EditorShortcut.selectTool(.arrow)),
            ("t", EditorShortcut.selectTool(.text)),
            ("R", EditorShortcut.selectTool(.rectangle)),
        ]
    )
    func editorKeyboardShortcutsResolve(
        key: String,
        expected: EditorShortcut
    ) {
        #expect(
            EditorShortcut.resolve(characters: key, modifiers: []) == expected
        )
    }

    @Test
    func rectangleIsTheDefaultTool() {
        let model = AnnotationEditorModel(sourceImage: testImage())

        #expect(model.tool == .rectangle)
    }

    @Test
    func editorKeyboardShortcutsIgnoreModifiedAndUnknownKeys() {
        #expect(
            EditorShortcut.resolve(characters: "s", modifiers: .command) == nil
        )
        #expect(
            EditorShortcut.resolve(characters: "x", modifiers: []) == nil
        )
    }

    @Test
    func undoRemovesOnlyTheMostRecentCommittedAnnotation() {
        let model = AnnotationEditorModel(sourceImage: testImage())
        model.commit(.arrow(start: .zero, end: CGPoint(x: 10, y: 10)))
        model.commit(.rectangle(start: .zero, end: CGPoint(x: 20, y: 20)))

        #expect(model.annotations.count == 2)
        #expect(model.undo())
        #expect(model.annotations.count == 1)
        #expect(model.undo())
        #expect(!model.undo())
    }

    @Test
    func moveCanBeUndoneAndRedoneAsOneChange() {
        let model = AnnotationEditorModel(sourceImage: testImage())
        model.commit(
            .rectangle(
                start: CGPoint(x: 10, y: 20),
                end: CGPoint(x: 40, y: 60)
            )
        )
        let original = model.annotations[0]
        let moved = AnnotationGeometry.translated(
            original,
            by: CGPoint(x: 15, y: 25)
        )

        #expect(model.replace(moved))
        #expect(model.annotations == [moved])
        #expect(model.undo())
        #expect(model.annotations == [original])
        #expect(model.redo())
        #expect(model.annotations == [moved])
    }

    @Test
    func removeCanBeUndoneAndNewChangeClearsRedo() {
        let model = AnnotationEditorModel(sourceImage: testImage())
        model.commit(.arrow(start: .zero, end: CGPoint(x: 10, y: 10)))
        let annotation = model.annotations[0]

        #expect(model.remove(id: annotation.id))
        #expect(model.annotations.isEmpty)
        #expect(model.undo())
        #expect(model.annotations == [annotation])
        model.commit(.pencil([CGPoint(x: 4, y: 4)]))
        #expect(!model.redo())
    }

    @Test
    func annotationHitTestingUsesStrokeTolerance() {
        let rectangle = Annotation(
            shape: .rectangle(
                start: CGPoint(x: 10, y: 10),
                end: CGPoint(x: 50, y: 50)
            ),
            style: AnnotationStyle(color: .red, thickness: .thin)
        )

        #expect(
            AnnotationGeometry.contains(
                CGPoint(x: 30, y: 13),
                annotation: rectangle,
                tolerance: 4
            )
        )
        #expect(
            !AnnotationGeometry.contains(
                CGPoint(x: 30, y: 30),
                annotation: rectangle,
                tolerance: 4
            )
        )
    }

    @Test
    func annotationMovementIsConstrainedToImageBounds() {
        let annotation = Annotation(
            shape: .rectangle(
                start: CGPoint(x: 20, y: 30),
                end: CGPoint(x: 60, y: 70)
            ),
            style: AnnotationStyle(color: .red, thickness: .medium)
        )

        #expect(
            AnnotationGeometry.constrainedTranslation(
                of: annotation,
                proposed: CGPoint(x: -100, y: 100),
                imageSize: CGSize(width: 200, height: 100)
            ) == CGPoint(x: -20, y: 30)
        )
    }

    @Test
    func committedAnnotationKeepsTheStyleSelectedAtDrawTime() {
        let model = AnnotationEditorModel(sourceImage: testImage())
        model.color = .blue
        model.thickness = .thick
        model.textSize = .large
        model.commit(.pencil([CGPoint(x: 1, y: 2)]))
        model.color = .yellow
        model.thickness = .thin
        model.textSize = .small

        #expect(model.annotations[0].style.color == .blue)
        #expect(model.annotations[0].style.thickness == .thick)
        #expect(model.annotations[0].style.textSize == .large)
    }

    @Test
    func aspectFitMappingAccountsForLetterboxing() {
        let imageRect = AnnotationRenderer.aspectFitRect(
            imageSize: CGSize(width: 200, height: 100),
            in: CGRect(x: 0, y: 0, width: 300, height: 300)
        )

        #expect(imageRect == CGRect(x: 0, y: 75, width: 300, height: 150))
        #expect(
            AnnotationRenderer.imagePoint(
                from: CGPoint(x: 150, y: 150),
                imageRect: imageRect,
                imageSize: CGSize(width: 200, height: 100)
            ) == CGPoint(x: 100, y: 50)
        )
        #expect(
            AnnotationRenderer.imagePoint(
                from: CGPoint(x: 150, y: 20),
                imageRect: imageRect,
                imageSize: CGSize(width: 200, height: 100)
            ) == nil
        )
    }

    @Test
    func dragCoordinatesClampToTheImageEdges() {
        let imageRect = CGRect(x: 20, y: 40, width: 200, height: 100)
        let imageSize = CGSize(width: 400, height: 200)

        #expect(
            AnnotationRenderer.clampedImagePoint(
                from: CGPoint(x: -100, y: 70),
                imageRect: imageRect,
                imageSize: imageSize
            ) == CGPoint(x: 0, y: 60)
        )
        #expect(
            AnnotationRenderer.clampedImagePoint(
                from: CGPoint(x: 500, y: 300),
                imageRect: imageRect,
                imageSize: imageSize
            ) == CGPoint(x: 400, y: 200)
        )
    }

    @Test
    func textPlacementKeepsEditorAndExportWidthUsableNearRightEdge() {
        let imageWidth: CGFloat = 200
        let displayScale: CGFloat = 0.5
        let originX = AnnotationTextLayout.adjustedOriginX(
            clickX: 195,
            imageWidth: imageWidth,
            displayScale: displayScale
        )
        let exportedWidth = imageWidth - originX

        #expect(originX == 120)
        #expect(exportedWidth * displayScale == AnnotationTextLayout.minimumViewWidth)
        #expect(
            AnnotationTextLayout.adjustedOriginX(
                clickX: 50,
                imageWidth: imageWidth,
                displayScale: displayScale
            ) == 50
        )
    }

    @Test
    func screenshotNamesUseANumericSuffixWhenTheTimestampAlreadyExists() {
        let directory = URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true)
        let firstURL = directory.appendingPathComponent(
            "Shot 2026-07-26 at 18.45.00.png"
        )
        let secondURL = ScreenshotFileNamer.availableURL(
            in: directory,
            timestamp: "2026-07-26 at 18.45.00",
            fileExists: { $0 == firstURL }
        )

        #expect(secondURL.lastPathComponent == "Shot 2026-07-26 at 18.45.00 2.png")
    }

    @Test
    func flatteningPreservesBackingPixelDimensions() throws {
        let source = testImage(points: CGSize(width: 100, height: 50), pixels: CGSize(width: 200, height: 100))
        let annotation = Annotation(
            shape: .rectangle(
                start: CGPoint(x: 10, y: 10),
                end: CGPoint(x: 90, y: 40)
            ),
            style: AnnotationStyle(color: .red, thickness: .medium)
        )

        let flattened = try #require(
            AnnotationRenderer.flattenedImage(source: source, annotations: [annotation])
        )
        let representation = try #require(
            flattened.representations.compactMap { $0 as? NSBitmapImageRep }.first
        )

        #expect(representation.pixelsWide == 200)
        #expect(representation.pixelsHigh == 100)
        #expect(flattened.size == CGSize(width: 100, height: 50))
    }

    @Test
    func flatteningWithoutAnnotationsPreservesSourcePixelOrientation() throws {
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 4,
                pixelsHigh: 4,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        bitmap.size = CGSize(width: 2, height: 2)
        let red = NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1)
        let blue = NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1)
        for y in 0..<4 {
            for x in 0..<4 {
                bitmap.setColor(y < 2 ? red : blue, atX: x, y: y)
            }
        }
        let source = NSImage(size: bitmap.size)
        source.addRepresentation(bitmap)

        let flattened = try #require(
            AnnotationRenderer.flattenedImage(source: source, annotations: [])
        )
        let result = try #require(
            flattened.representations.compactMap { $0 as? NSBitmapImageRep }.first
        )

        #expect(result.colorAt(x: 1, y: 0)?.redComponent ?? 0 > 0.8)
        #expect(result.colorAt(x: 1, y: 0)?.blueComponent ?? 1 < 0.2)
        #expect(result.colorAt(x: 1, y: 3)?.blueComponent ?? 0 > 0.8)
        #expect(result.colorAt(x: 1, y: 3)?.redComponent ?? 1 < 0.2)
    }

    @Test
    func flattenedAnnotationUsesCanvasTopLeftCoordinates() throws {
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 40,
                pixelsHigh: 40,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        bitmap.size = CGSize(width: 20, height: 20)
        let white = NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1)
        for y in 0..<40 {
            for x in 0..<40 {
                bitmap.setColor(white, atX: x, y: y)
            }
        }
        let source = NSImage(size: bitmap.size)
        source.addRepresentation(bitmap)
        let topStroke = Annotation(
            shape: .pencil([
                CGPoint(x: 5, y: 2),
                CGPoint(x: 15, y: 2),
            ]),
            style: AnnotationStyle(color: .black, thickness: .thin)
        )

        let flattened = try #require(
            AnnotationRenderer.flattenedImage(source: source, annotations: [topStroke])
        )
        let result = try #require(
            flattened.representations.compactMap { $0 as? NSBitmapImageRep }.first
        )

        #expect(result.colorAt(x: 20, y: 4)?.redComponent ?? 1 < 0.2)
        #expect(result.colorAt(x: 20, y: 35)?.redComponent ?? 0 > 0.8)
    }

    @Test
    func clipboardEncodingKeepsRectangleAtItsCanvasPosition() throws {
        let source = testImage(
            points: CGSize(width: 100, height: 100),
            pixels: CGSize(width: 200, height: 200)
        )
        let annotation = Annotation(
            shape: .rectangle(
                start: CGPoint(x: 20, y: 60),
                end: CGPoint(x: 80, y: 80)
            ),
            style: AnnotationStyle(color: .red, thickness: .medium)
        )
        let flattened = try #require(
            AnnotationRenderer.flattenedImage(source: source, annotations: [annotation])
        )
        let tiff = try #require(flattened.tiffRepresentation)
        let clipboardImage = try #require(NSBitmapImageRep(data: tiff))

        let expectedStroke = try #require(clipboardImage.colorAt(x: 40, y: 140))
        let mirroredPosition = try #require(clipboardImage.colorAt(x: 40, y: 80))
        #expect(expectedStroke.redComponent > 0.8)
        #expect(expectedStroke.greenComponent < 0.5)
        #expect(expectedStroke.alphaComponent > 0.8)
        #expect(mirroredPosition.alphaComponent < 0.2)
    }

    @Test
    func flattenedTextAppearsNearItsTopLeftCanvasOrigin() throws {
        let source = testImage(
            points: CGSize(width: 120, height: 80),
            pixels: CGSize(width: 120, height: 80)
        )
        let annotation = Annotation(
            shape: .text(
                origin: CGPoint(x: 10, y: 8),
                text: "Text",
                maxWidth: 100
            ),
            style: AnnotationStyle(
                color: .black,
                thickness: .medium,
                textSize: .large
            )
        )

        let flattened = try #require(
            AnnotationRenderer.flattenedImage(source: source, annotations: [annotation])
        )
        let result = try #require(
            flattened.representations.compactMap { $0 as? NSBitmapImageRep }.first
        )
        var darkPixelCount = 0
        var darkMinY = result.pixelsHigh
        var darkMaxY = 0
        for y in 0..<result.pixelsHigh {
            for x in 0..<result.pixelsWide {
                guard let color = result.colorAt(x: x, y: y) else { continue }
                if color.alphaComponent > 0.5,
                   color.redComponent < 0.5,
                   color.greenComponent < 0.5,
                   color.blueComponent < 0.5 {
                    darkPixelCount += 1
                    darkMinY = min(darkMinY, y)
                    darkMaxY = max(darkMaxY, y)
                }
            }
        }

        #expect(darkPixelCount > 100)
        #expect(darkMinY >= 8)
        #expect(darkMinY < 30)
        #expect(darkMaxY < 50)
    }

    private func testImage(
        points: CGSize = CGSize(width: 100, height: 100),
        pixels: CGSize = CGSize(width: 100, height: 100)
    ) -> NSImage {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixels.width),
            pixelsHigh: Int(pixels.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        bitmap.size = points
        let image = NSImage(size: points)
        image.addRepresentation(bitmap)
        return image
    }
}
