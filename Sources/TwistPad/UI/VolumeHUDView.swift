import SwiftUI

final class HUDModel: ObservableObject {
    @Published var level: Double = 0
    @Published var detents: Int = 16
    @Published var isMuted: Bool = false
    /// nil shows the volume dial; true or false shows a track skip arrow.
    @Published var trackSkipForward: Bool?
}

/// Sizes the panel has to match, since the track skip is deliberately much
/// smaller than the volume dial.
enum HUDSize {
    static let volume = CGSize(width: 160, height: 160)
    static let trackSkip = CGSize(width: 96, height: 72)
}

struct VolumeHUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        Group {
            if let forward = model.trackSkipForward {
                // A skip is a confirmation, not a readout: you already know what
                // you did, so it only has to be big enough to catch the eye.
                Image(systemName: forward ? "forward.end.fill" : "backward.end.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: HUDSize.trackSkip.width - 36,
                           height: HUDSize.trackSkip.height - 36)
                    .padding(18)
            } else {
                dial
                    .frame(width: 116, height: 116)
                    .padding(22)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: model.trackSkipForward == nil ? 30 : 20,
                             style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: model.trackSkipForward == nil ? 30 : 20,
                             style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
        )
    }

    private var dial: some View {
        DialGauge(level: model.level, detents: model.detents) {
            VStack(spacing: 1) {
                Image(systemName: speakerSymbolName(level: model.level,
                                                    isMuted: model.isMuted))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.identity)

                Text("\(Int((model.level * 100).rounded()))")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        }
    }
}
