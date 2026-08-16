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
    /// How far the midpoint between the fingers has moved since touch-down, mm.
    let centroidDrift: Double
    /// Distance between the contacts when they landed, mm.
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
/// Distances are millimetres, never normalized trackpad units. The sensor is far
/// wider than it is deep, so the same physical gap measures about 1.6x larger
/// with the fingers stacked vertically than side by side. Gates written in
/// normalized units silently let vertical two-finger scrolls through.
///
/// A scroll does rotate a little, because two fingers never travel exactly
/// together, so rotation alone cannot separate the two. What actually separates
/// them is that a twist pivots without going anywhere: the midpoint between the
/// fingers barely moves, while a scroll drags it across the pad.
final class DialRecognizer {

    weak var delegate: DialRecognizerDelegate?

    /// Rotation required before the dial takes control, degrees. Spent arming
    /// rather than applied, so engaging feels like the free play at the start of
    /// a real knob.
    var activationThreshold: Double = 8

    /// The real defence against scrolls, in degrees of rotation per millimetre
    /// of travel. A twist pivots in place, turning several degrees for every
    /// millimetre the midpoint moves. A scroll is the opposite: it covers
    /// distance and only rotates because two fingers never travel exactly
    /// together. Comparing the two rates is scale-free, so it does not depend on
    /// how fast or how far any particular person twists.
    var minDegreesPerMillimetre: Double = 3.0

    /// Backstop for the ratio above, mm. Stops applying once engaged, because a
    /// long twist naturally wanders.
    var maxDriftWhileArming: Double = 10

    /// Stance width, mm. Thumb and index sit wider apart than the index and
    /// middle pair used for scrolling. Deliberately loose, because the rate test
    /// does the real work and an over-tight stance gate silently kills the
    /// gesture for anyone who holds their fingers closer together.
    var minSeparation: Double = 24
    var maxSeparation: Double = 115

    /// Contacts shift as they flatten out under pressure, which shows up as a
    /// few degrees of rotation that nobody intended. Ignore the settling frames.
    var settlingFrames: Int = 2

    /// Release if an engaged gesture goes quiet without an end phase. A dial
    /// stuck on is worse than one that lets go early.
    var idleTimeout: TimeInterval = 0.35

    private enum State {
        case idle
        case arming(accumulated: Double, frames: Int)
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
            state = stanceIsPlausible(sample) ? .arming(accumulated: 0, frames: 0) : .rejected
            armWatchdog()

        case .changed:
            switch state {
            case .rejected:
                break
            case .idle:
                state = stanceIsPlausible(sample) ? .arming(accumulated: 0, frames: 0) : .rejected
                evaluateArming(sample)
            case .arming(let accumulated, let frames):
                let next = frames + 1
                state = next <= settlingFrames
                    ? .arming(accumulated: accumulated, frames: next)
                    : .arming(accumulated: accumulated + sample.deltaDegrees, frames: next)
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
        guard case .arming(let accumulated, _) = state else { return }

        if sample.centroidDrift > maxDriftWhileArming {
            state = .rejected
            return
        }

        guard abs(accumulated) >= activationThreshold else { return }

        // Floor the divisor: a twist that pivots almost perfectly would other-
        // wise divide by something near zero.
        let rate = abs(accumulated) / max(sample.centroidDrift, 0.5)
        guard rate >= minDegreesPerMillimetre else {
            // Travelling too far for the rotation involved. Not a twist, and it
            // will not become one, so ignore the rest of this contact.
            state = .rejected
            return
        }

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
