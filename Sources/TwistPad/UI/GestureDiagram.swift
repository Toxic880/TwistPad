import SwiftUI

/// A small trackpad with dots for fingers, in the spirit of System Settings.
///
/// Laid out for a right hand, since most people have one: thumb low and left,
/// fingers up and right. A left-handed hand makes the same shapes mirrored, and
/// the gesture itself does not care.
struct GestureDiagram: View {

    enum Kind {
        case twist
        case pinch
    }

    let kind: Kind

    // Normalized positions on the pad, x right and y down.
    private var thumb: CGPoint { CGPoint(x: 0.33, y: 0.71) }
    private var indexFinger: CGPoint {
        kind == .twist ? CGPoint(x: 0.64, y: 0.32) : CGPoint(x: 0.62, y: 0.30)
    }
    private var middleFinger: CGPoint { CGPoint(x: 0.76, y: 0.38) }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let corner = size.width * 0.085

            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)

                guide(in: size)

                dot(at: thumb, in: size, diameter: size.height * 0.20)
                dot(at: indexFinger, in: size, diameter: size.height * 0.16)
                if kind == .pinch {
                    dot(at: middleFinger, in: size, diameter: size.height * 0.16)
                }
            }
        }
        .aspectRatio(1.6, contentMode: .fit)
    }

    @ViewBuilder
    private func guide(in size: CGSize) -> some View {
        switch kind {
        case .twist:
            let a = point(thumb, size)
            let b = point(indexFinger, size)
            let centre = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let radius = (((b.x - a.x) * (b.x - a.x))
                          + ((b.y - a.y) * (b.y - a.y))).squareRoot() / 2

            Circle()
                .stroke(Color.accentColor.opacity(0.45),
                        style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                .frame(width: radius * 2, height: radius * 2)
                .position(centre)

            Image(systemName: "arrow.clockwise")
                .font(.system(size: size.height * 0.19, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .position(centre)

        case .pinch:
            let a = point(thumb, size)
            let fingersMid = CGPoint(
                x: (point(indexFinger, size).x + point(middleFinger, size).x) / 2,
                y: (point(indexFinger, size).y + point(middleFinger, size).y) / 2)
            let centre = CGPoint(x: (a.x + fingersMid.x) / 2, y: (a.y + fingersMid.y) / 2)
            let angle = atan2(fingersMid.y - a.y, fingersMid.x - a.x) * 180 / .pi

            Path { path in
                path.move(to: a)
                path.addLine(to: fingersMid)
            }
            .stroke(Color.accentColor.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))

            Image(systemName: "arrow.left.and.right")
                .font(.system(size: size.height * 0.19, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .rotationEffect(.degrees(angle))
                .position(centre)
        }
    }

    private func dot(at position: CGPoint, in size: CGSize, diameter: CGFloat) -> some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: diameter, height: diameter)
            .position(point(position, size))
    }

    private func point(_ normalized: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: normalized.x * size.width, y: normalized.y * size.height)
    }
}
