import AppKit

/// A plain-text report someone can paste into an issue or an email.
///
/// Reports what was actually measured rather than a verdict, so a wrong guess on
/// our side is still debuggable by whoever reads it.
enum Diagnostics {

    static func report(dial: VolumeDial) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let settings = Settings.shared
        let source = MultitouchDialSource.shared

        var lines: [String] = []
        lines.append("TwistPad \(version) (\(build))")
        lines.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("\(sysctlString("hw.model")) \(machineArchitecture())")
        lines.append("")

        lines.append("Trackpad")
        lines.append("  MultitouchSupport loaded : \(yesNo(MultitouchSupport.isAvailable))")
        lines.append("  MTTouch layout 96 bytes  : \(yesNo(MultitouchSupport.isLayoutSane))")
        lines.append("  devices seen             : \(source.deviceCount)")
        lines.append(String(format: "  sensor surface           : %.0f x %.0f mm",
                            source.surfaceWidth, source.surfaceHeight))
        lines.append("  gesture running          : \(yesNo(source.isRunning))")
        lines.append("")

        lines.append("Haptics")
        lines.append("  actuator opens           : \(yesNo(Haptics.hasHardware))")
        lines.append("  ActuateDetents           : \(trackpadDefault("ActuateDetents"))")
        lines.append("  ForceSuppressed          : \(trackpadDefault("ForceSuppressed"))")
        lines.append("  system feedback enabled  : \(yesNo(Haptics.isEnabledInSystemSettings))")
        lines.append("  status                   : \(describe(Haptics.availability))")
        lines.append("  preference               : \(settings.hapticsEnabled ? "on" : "off")")
        lines.append("")

        lines.append("Audio")
        lines.append("  output device            : \(dial.outputDeviceName)")
        lines.append("  volume control           : \(dial.volumeController.strategyDescription)")
        lines.append(String(format: "  current level            : %.0f%%", dial.volumeLevel * 100))
        lines.append("")

        lines.append("Gesture settings")
        lines.append("  enabled                  : \(yesNo(settings.isEnabled))")
        lines.append(String(format: "  full sweep               : %.0f deg",
                            settings.degreesForFullSweep))
        lines.append(String(format: "  dead zone                : %.0f deg",
                            settings.activationThreshold))
        lines.append("  detents                  : \(settings.detentCount == 0 ? "smooth" : String(settings.detentCount))")
        lines.append("  reversed                 : \(yesNo(settings.invertDirection))")

        return lines.joined(separator: "\n")
    }

    static func copyToPasteboard(dial: VolumeDial) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report(dial: dial), forType: .string)
    }

    // MARK: - Helpers

    private static func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }

    private static func describe(_ availability: Haptics.Availability) -> String {
        switch availability {
        case .working: return "should work"
        case .noHardware: return "no actuator found"
        case .disabledInSystemSettings: return "turned off in System Settings"
        }
    }

    /// Reports the raw value including whether the key was ever set, because
    /// "unset" and "0" mean different things here.
    private static func trackpadDefault(_ key: String) -> String {
        let domains = [
            "com.apple.AppleMultitouchTrackpad",
            "com.apple.driver.AppleBluetoothMultitouch.trackpad",
        ]
        var parts: [String] = []
        for domain in domains {
            guard let defaults = UserDefaults(suiteName: domain),
                  let value = defaults.object(forKey: key) else { continue }
            parts.append("\(domain.hasPrefix("com.apple.driver") ? "bluetooth" : "builtin")=\(value)")
        }
        return parts.isEmpty ? "unset" : parts.joined(separator: " ")
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: buffer)
    }

    private static func machineArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown-arch"
        #endif
    }
}
