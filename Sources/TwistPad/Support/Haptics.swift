import AppKit

/// Detent clicks, plus the ability to say why they are missing.
///
/// Firing goes through the public `NSHapticFeedbackManager`, which respects the
/// user's trackpad preferences. It is silent when it cannot do anything, so the
/// checks below exist to tell the difference between "working", "this Mac has no
/// Taptic Engine", and "switched off in System Settings".
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

    // MARK: - Diagnosis

    /// Cached: probing creates and opens a device, which is not free.
    private static var cachedHardware: Bool?

    /// False on any Mac without a Taptic Engine, which includes pre-2015
    /// MacBooks and the original Magic Trackpad.
    static var hasHardware: Bool {
        if let cachedHardware { return cachedHardware }
        let result = MultitouchSupport.hasHapticHardware()
        cachedHardware = result
        return result
    }

    /// Mirrors "Force Click and haptic feedback" in System Settings > Trackpad.
    /// Absent keys mean the default, which is on.
    static var isEnabledInSystemSettings: Bool {
        let domains = [
            "com.apple.AppleMultitouchTrackpad",
            "com.apple.driver.AppleBluetoothMultitouch.trackpad",
        ]
        for domain in domains {
            guard let defaults = UserDefaults(suiteName: domain) else { continue }
            if defaults.object(forKey: "ForceSuppressed") != nil,
               defaults.bool(forKey: "ForceSuppressed") {
                return false
            }
            if defaults.object(forKey: "ActuateDetents") != nil,
               !defaults.bool(forKey: "ActuateDetents") {
                return false
            }
        }
        return true
    }

    enum Availability {
        case working
        case noHardware
        case disabledInSystemSettings
    }

    static var availability: Availability {
        if !hasHardware { return .noHardware }
        if !isEnabledInSystemSettings { return .disabledInSystemSettings }
        return .working
    }

    /// Fires a short burst so the user can confirm for themselves.
    static func test() {
        for step in 0..<5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.12) {
                lastClick = 0
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange,
                                                                 performanceTime: .now)
            }
        }
    }

    static func openTrackpadSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.Trackpad-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
