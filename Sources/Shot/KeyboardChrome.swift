import AppKit

/// Crosshair, badge, and help-panel drawing shared by the keyboard-driven
/// selection overlay and the image editor canvas. Every routine works in
/// flipped and unflipped views, so both callers can pass their own rect.
enum KeyboardChrome {
    private static let padding = CGSize(width: 7, height: 4)

    private static var labelAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
    }

    static func drawCrosshair(at point: CGPoint, in rect: CGRect) {
        NSColor.white.withAlphaComponent(0.6).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: CGPoint(x: rect.minX, y: point.y + 0.5))
        path.line(to: CGPoint(x: rect.maxX, y: point.y + 0.5))
        path.move(to: CGPoint(x: point.x + 0.5, y: rect.minY))
        path.line(to: CGPoint(x: point.x + 0.5, y: rect.maxY))
        path.stroke()
    }

    static func labelSize(_ text: String) -> CGSize {
        let size = (text as NSString).size(withAttributes: labelAttributes)
        return CGSize(
            width: size.width + padding.width * 2,
            height: size.height + padding.height * 2
        )
    }

    static func drawLabel(_ text: String, in frame: CGRect) {
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 4, yRadius: 4).fill()
        // `draw(at:)` reads the point as the top-left in a flipped view and the
        // bottom-left otherwise, so this insets the text either way.
        (text as NSString).draw(
            at: CGPoint(x: frame.minX + padding.width, y: frame.minY + padding.height),
            withAttributes: labelAttributes
        )
    }

    static func drawBadge(_ text: String, near point: CGPoint, in rect: CGRect) {
        let size = labelSize(text)
        let gap: CGFloat = 14
        var origin = CGPoint(x: point.x + gap, y: point.y + gap)
        if origin.x + size.width > rect.maxX {
            origin.x = point.x - gap - size.width
        }
        if origin.y + size.height > rect.maxY {
            origin.y = point.y - gap - size.height
        }
        origin.x = max(origin.x, rect.minX)
        origin.y = max(origin.y, rect.minY)
        drawLabel(text, in: CGRect(origin: origin, size: size))
    }

    static func drawHelp(
        title: String,
        rows: [(keys: String, action: String)],
        in rect: CGRect
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 150)]
        paragraph.defaultTabInterval = 150
        paragraph.lineSpacing = 3

        let text = NSMutableAttributedString(
            string: "\(title)\n\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
            ]
        )
        let rowAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            .paragraphStyle: paragraph,
        ]
        for row in rows {
            text.append(
                NSAttributedString(
                    string: "\(row.keys)\t\(row.action)\n",
                    attributes: rowAttributes
                )
            )
        }

        let inset: CGFloat = 18
        // `.usesLineFragmentOrigin` lays the rows out from the top of the rect
        // downward in flipped and unflipped views alike.
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin]
        let measured = text.boundingRect(
            with: CGSize(width: 460, height: max(rect.height - inset * 2, 1)),
            options: options
        ).size
        let frame = CGRect(
            x: rect.midX - (ceil(measured.width) + inset * 2) / 2,
            y: rect.midY - (ceil(measured.height) + inset * 2) / 2,
            width: ceil(measured.width) + inset * 2,
            height: ceil(measured.height) + inset * 2
        )

        NSColor.black.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 10, yRadius: 10).fill()
        NSColor.white.withAlphaComponent(0.25).setStroke()
        let border = NSBezierPath(
            roundedRect: frame.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 10,
            yRadius: 10
        )
        border.lineWidth = 1
        border.stroke()

        text.draw(with: frame.insetBy(dx: inset, dy: inset), options: options)
    }
}
