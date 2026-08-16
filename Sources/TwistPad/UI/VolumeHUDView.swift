import SwiftUI

final class HUDModel: ObservableObject {
    @Published var level: Double = 0
    @Published var detents: Int = 16
    @Published var isMuted: Bool = false
}

struct VolumeHUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
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
        .frame(width: 116, height: 116)
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
    }
}
