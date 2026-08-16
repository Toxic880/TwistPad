import AppKit

/// Posts the system media keys, which is how every app controls playback
/// regardless of the player: Music, Spotify, and anything in a browser all
/// listen for these.
///
/// Unlike the volume dial, this needs Accessibility permission. Verified by
/// posting a volume key with permission withheld: nothing happened. So the
/// permission is requested only when someone turns track control on, and
/// TwistPad still needs nothing at all if they leave it off.
enum MediaKeys {

    enum Key: Int32 {
        case next = 17
        case previous = 18
        case playPause = 16
    }

    static var hasPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt with the button that opens Privacy & Security.
    /// Returns the state before the prompt, since the answer arrives later.
    @discardableResult
    static func requestPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    static func post(_ key: Key) {
        guard hasPermission else { return }
        send(key.rawValue, down: true)
        send(key.rawValue, down: false)
    }

    /// The aux-control format: subtype 8, with the key and its up/down state
    /// packed into `data1` and mirrored in the modifier flags.
    private static func send(_ code: Int32, down: Bool) {
        let state: Int32 = down ? 0x0A00 : 0x0B00
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((code << 16) | state),
            data2: -1) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
