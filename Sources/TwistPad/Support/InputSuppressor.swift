import AppKit

/// Swallows scroll and gesture events while a TwistPad gesture is engaged.
///
/// Reading contacts at the driver level means macOS still sees the same fingers
/// and draws its own conclusions, so a twist scrolls the page underneath and a
/// pinch nudges the view. The only way to stop that is an event tap, which needs
/// Accessibility permission, so this is off unless that has been granted.
///
/// A tap that drops events is a good way to break someone's trackpad, so the
/// suppression window is bounded twice over: it only opens once a gesture has
/// actually engaged, and a watchdog forces it shut if it ever stays open.
final class InputSuppressor {

    static let shared = InputSuppressor()

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var forceOffTimer: Timer?

    private(set) var isRunning = false

    private init() {}

    /// Longest a gesture could plausibly hold input. The recognisers give up
    /// after 0.35s of silence, so anything approaching this is a bug.
    private let maximumSuppression: TimeInterval = 5

    var isSuppressing: Bool {
        get { suppressionActive }
        set {
            guard suppressionActive != newValue else { return }
            suppressionActive = newValue

            forceOffTimer?.invalidate()
            forceOffTimer = nil
            guard newValue else { return }

            forceOffTimer = Timer.scheduledTimer(withTimeInterval: maximumSuppression,
                                                 repeats: false) { _ in
                NSLog("TwistPad: suppression watchdog fired; releasing input")
                suppressionActive = false
            }
        }
    }

    @discardableResult
    func start() -> Bool {
        guard !isRunning, AXIsProcessTrusted() else { return false }

        // Scroll plus the gesture family. These raw values are not in the public
        // CGEventType enum, but the tap masks on them just the same.
        let types: [UInt64] = [
            22,  // scrollWheel
            18,  // rotate
            19,  // beginGesture
            20,  // endGesture
            29,  // gesture
            30,  // magnify
            31,  // swipe
            32,  // smartMagnify
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1) }

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: suppressorCallback,
                                          userInfo: nil) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        isRunning = true
        return true
    }

    func stop() {
        isSuppressing = false
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isRunning = false
    }

    /// macOS disables a tap whose callback ever runs long. Turning it back on is
    /// the difference between a hiccup and the feature silently dying.
    fileprivate func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

/// Read from the event tap thread, written from main. A plain Bool is fine here:
/// a torn read would at worst drop or pass one frame's event.
private var suppressionActive = false

private let suppressorCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        InputSuppressor.shared.reenable()
        return Unmanaged.passUnretained(event)
    }
    if suppressionActive {
        return nil
    }
    return Unmanaged.passUnretained(event)
}
