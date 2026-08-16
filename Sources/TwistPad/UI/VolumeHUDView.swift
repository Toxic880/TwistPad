import SwiftUI

final class HUDModel: ObservableObject {
    @Published var level: Double = 0
    @Published var detents: Int = 16
    @Published var isMuted: Bool = false
}

/// The on-screen readout: a segmented dial where one segment is one detent, so
/// what you see lighting up is exactly what you felt click under your fingers.
///
/// Angles are `φ`, clockwise from 3 o'clock, matching where `Circle().trim` and
/// `rotationEffect` both start. The sweep is 270° with its gap at the bottom,
/// running from φ=135° round to φ=405°.
struct VolumeHUDView: View {
    @ObservedObject var model: HUDModel

    private let sweepFraction = 0.75
    private let arcStart = 135.0
    private let ringSize: CGFloat = 116
    private let lineWidth: CGFloat = 8

    private var symbolName: String {
        if model.isMuted || model.level <= 0.001 { return "speaker.slash.fill" }
        if model.level < 0.33 { return "speaker.wave.1.fill" }
        if model.level < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if model.detents > 0 {
                    segmentedDial(count: model.detents)
                } else {
                    continuousDial()
                }

                VStack(spacing: 1) {
                    Image(systemName: symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .contentTransition(.identity)

                    Text("\(Int((model.level * 100).rounded()))")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: ringSize, height: ringSize)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
        )
        // No implicit animation: the dial tracks the fingers 1:1, and smoothing
        // here would read as lag in the gesture itself.
        .animation(nil, value: model.level)
    }

    private func segmentedDial(count: Int) -> some View {
        let lit = model.level * Double(count)
        // Gap between segments, as a fraction of one segment's arc.
        let gap = 0.17

        return ZStack {
            ForEach(0..<count, id: \.self) { index in
                let start = Double(index) / Double(count)
                let end = Double(index + 1) / Double(count)
                let inset = (end - start) * gap / 2
                let isLit = Double(index) < lit - 0.001

                Circle()
                    .trim(from: sweepFraction * (start + inset),
                          to: sweepFraction * (end - inset))
                    .stroke(Color.primary.opacity(isLit ? 0.95 : 0.13),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(arcStart))
            }
        }
    }

    private func continuousDial() -> some View {
        ZStack {
            Circle()
                .trim(from: 0, to: sweepFraction)
                .stroke(Color.primary.opacity(0.13),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(arcStart))

            if model.level > 0.001 {
                Circle()
                    .trim(from: 0, to: sweepFraction * model.level)
                    .stroke(Color.primary.opacity(0.95),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(arcStart))
            }
        }
    }
}
