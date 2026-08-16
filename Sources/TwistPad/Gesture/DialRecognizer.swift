import Foundation

enum GesturePhase {
    case began
    case changed
    case ended
    case cancelled
}

struct TwistSample {
    /// Change in the contact pair's orientation since the last frame, positive
    /// counter-clockwise, already unwrapped.
    let deltaDegrees: Double
    /// How far the midpoint between the fingers has moved since touch-down.
    let centroidDrift: Double
    let initialSeparation: Double
    let phase: GesturePhase
}

protocol DialRecognizerDelegate: AnyObject {
    func dialDidEngage(_ recognizer: DialRecognizer)
    func dial(_ recognizer: DialRecognizer, didRotateBy degrees: Double)
    func dialDidDisengage(_ recognizer: DialRecognizer)
}

/// Decides when a two-finger contact is a deliberate volume twist.
///
/// Measured over 48 twists and 21 scrolls, rotation alone separates the two by
/// only ~2°, so drift and stance width have to agree before engaging:
/// twists run 21°–183° with drift ≤ 0.11 and separation 0.20–0.59, while
/// scrolls stay under 19° but drift up to 0.24 at separation 0.14–0.18.
final class DialRecognizer {

    weak var delegate: DialRecognizerDelegate?

    /// Spent arming rather than applied, so engaging feels like the free play at
    /// the start of a real knob. Kept small: every degree here is wrist travel
    /// unavailable for setting the volume.
    var activationThreshold: Double = 8

    /// Only applies while arming; a long twist naturally wanders.
    var maxDriftWhileArming: Double = 0.08

    var minSeparation: Double = 0.19
    var maxSeparation: Double = 0.80

    /// Release if an engaged gesture goes quiet without an end phase. A dial
    /// stuck on is worse than one that lets go early.
    var idleTimeout: TimeInterval = 0.35

    private enum State {
        case idle
        case arming(accumulated: Double)
        case engaged
        /// Disqualified; ignore until the fingers lift.
        case rejected
    }

    private var state: State = .idle
    private var watchdog: Timer?
    private var lastEventTime: TimeInterval = 0

    var isEngaged: Bool {
        if case .engaged = state { return true }
        return false
    }

    func handle(_ sample: TwistSample) {
        switch sample.phase {
        case .began:
            // Notify, not silent: if a previous gesture was still engaged when a
            // new one starts, swallowing the disengage strands the dial "on" and
            // the HUD never hides.
            reset(notify: true)
            state = stanceIsPlausible(sample) ? .arming(accumulated: 0) : .rejected
            armWatchdog()

        case .changed:
            switch state {
            case .rejected:
                break
            case .idle:
                state = stanceIsPlausible(sample) ? .arming(accumulated: sample.deltaDegrees)
                                                  : .rejected
                evaluateArming(sample)
            case .arming(let accumulated):
                state = .arming(accumulated: accumulated + sample.deltaDegrees)
                evaluateArming(sample)
            case .engaged:
                delegate?.dial(self, didRotateBy: sample.deltaDegrees)
            }
            armWatchdog()

        case .ended, .cancelled:
            reset(notify: true)
        }
    }

    func abort() {
        reset(notify: true)
    }

    private func stanceIsPlausible(_ sample: TwistSample) -> Bool {
        sample.initialSeparation >= minSeparation
            && sample.initialSeparation <= maxSeparation
    }

    private func evaluateArming(_ sample: TwistSample) {
        guard case .arming(let accumulated) = state else { return }

        if sample.centroidDrift > maxDriftWhileArming {
            state = .rejected
            return
        }

        guard abs(accumulated) >= activationThreshold else { return }
        state = .engaged
        delegate?.dialDidEngage(self)
    }

    /// One repeating timer for the life of the gesture, rather than a fresh
    /// one-shot per frame: contacts arrive at up to 120 Hz, and allocating and
    /// invalidating that many timers a second is pure waste.
    private func armWatchdog() {
        lastEventTime = ProcessInfo.processInfo.systemUptime
        guard watchdog == nil else { return }
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if ProcessInfo.processInfo.systemUptime - self.lastEventTime > self.idleTimeout {
                self.reset(notify: true)
            }
        }
    }

    private func reset(notify: Bool) {
        watchdog?.invalidate()
        watchdog = nil
        let wasEngaged = isEngaged
        state = .idle
        if notify && wasEngaged {
            delegate?.dialDidDisengage(self)
        }
    }
}
