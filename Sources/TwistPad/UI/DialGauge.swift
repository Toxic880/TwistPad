import SwiftUI

/// The segmented dial, shared by the HUD and the settings preview. One segment
/// per detent, so what lights up is what you felt click.
///
/// Angles are `φ`, clockwise from 3 o'clock, matching where `Circle().trim` and
/// `rotationEffect` both start. The sweep is 270° with its gap at the bottom,
/// running from φ=135° round to φ=405°.
struct DialGauge<Center: View>: View {

    let level: Double
    let detents: Int
    var lineWidth: CGFloat = 8
    let center: Center

    init(level: Double,
         detents: Int,
         lineWidth: CGFloat = 8,
         @ViewBuilder center: () -> Center) {
        self.level = level
        self.detents = detents
        self.lineWidth = lineWidth
        self.center = center()
    }

    private let sweepFraction = 0.75
    private let arcStart = 135.0

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                if detents > 0 {
                    segmented(count: detents, radius: side / 2)
                } else {
                    continuous
                }
                center
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        // No implicit animation: the dial tracks the fingers 1:1, and smoothing
        // here would read as lag in the gesture itself.
        .animation(nil, value: level)
    }

    private func segmented(count: Int, radius: CGFloat) -> some View {
        let lit = level * Double(count)

        // A round cap sticks out by half the line width past the end of the arc.
        // Trimming without accounting for that makes neighbouring segments
        // overlap, and the dial renders as one solid arc instead of detents.
        let capDegrees = Double(lineWidth / 2 / max(radius, 1)) * 180 / .pi
        let capFraction = capDegrees / 360
        let breathingRoom = 0.004

        return ZStack {
            ForEach(0..<count, id: \.self) { index in
                let start = Double(index) / Double(count)
                let end = Double(index + 1) / Double(count)
                let inset = min(capFraction + breathingRoom, (end - start) * 0.42)

                Circle()
                    .trim(from: sweepFraction * (start + inset),
                          to: sweepFraction * (end - inset))
                    .stroke(Color.primary.opacity(Double(index) < lit - 0.001 ? 0.95 : 0.13),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(arcStart))
            }
        }
    }

    private var continuous: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: sweepFraction)
                .stroke(Color.primary.opacity(0.13),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(arcStart))

            if level > 0.001 {
                Circle()
                    .trim(from: 0, to: sweepFraction * level)
                    .stroke(Color.primary.opacity(0.95),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(arcStart))
            }
        }
    }
}

/// Speaker glyph matching a level, shared by the HUD and settings.
func speakerSymbolName(level: Double, isMuted: Bool) -> String {
    if isMuted || level <= 0.001 { return "speaker.slash.fill" }
    if level < 0.33 { return "speaker.wave.1.fill" }
    if level < 0.66 { return "speaker.wave.2.fill" }
    return "speaker.wave.3.fill"
}
