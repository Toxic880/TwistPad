import AppKit

/// Detent clicks. No-op on trackpads without a haptic engine.
enum Haptics {

    private static var lastClick: TimeInterval = 0
    private static let minimumInterval: TimeInterval = 0.018

    static func detentClick() {
        perform(.levelChange)
    }

    /// Firmer tap for hitting either end of the range.
    static func limitTap() {
        perform(.alignment)
    }

    private static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastClick >= minimumInterval else { return }
        lastClick = now
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
