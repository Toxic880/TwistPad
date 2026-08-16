import AppKit

/// The menu bar glyph: a knurled knob whose pointer tracks the current level.
///
/// Drawn rather than using an SF Symbol so the pointer can rotate — the icon
/// reads as the same object you just turned. Rendered as a template image, so
/// only the alpha channel matters and macOS tints it for the current menu bar.
enum MenuBarIcon {

    private static let side: CGFloat = 18
    private static let knurlCount = 12

    static func image(level: Double, muted: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let center = CGPoint(x: side / 2, y: side / 2)

            let knurls = NSBezierPath()
            knurls.lineWidth = 1.1
            knurls.lineCapStyle = .round
            for index in 0..<knurlCount {
                let angle = Double(index) / Double(knurlCount) * 2 * .pi
                knurls.move(to: point(from: center, angle: angle, radius: 6.3))
                knurls.line(to: point(from: center, angle: angle, radius: 7.5))
            }
            NSColor.black.withAlphaComponent(0.45).setStroke()
            knurls.stroke()

            let knobRadius: CGFloat = 5.3
            let knob = NSBezierPath(ovalIn: CGRect(
                x: center.x - knobRadius, y: center.y - knobRadius,
                width: knobRadius * 2, height: knobRadius * 2))
            knob.lineWidth = 1.3
            NSColor.black.withAlphaComponent(0.85).setStroke()
            knob.stroke()

            // Same 270° sweep as the HUD, measured clockwise from 3 o'clock.
            let phi = 135 + 270 * level
            let theta = -phi * .pi / 180
            let pointer = NSBezierPath()
            pointer.lineWidth = 1.7
            pointer.lineCapStyle = .round
            pointer.move(to: point(from: center, angle: theta, radius: 1.1))
            pointer.line(to: point(from: center, angle: theta, radius: 4.2))
            NSColor.black.setStroke()
            pointer.stroke()

            if muted {
                let slash = NSBezierPath()
                slash.lineWidth = 1.5
                slash.lineCapStyle = .round
                slash.move(to: CGPoint(x: 3.4, y: 3.4))
                slash.line(to: CGPoint(x: side - 3.4, y: side - 3.4))
                NSColor.black.setStroke()
                slash.stroke()
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    private static func point(from center: CGPoint, angle: Double, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius)
    }
}
