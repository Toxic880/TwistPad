import Foundation

protocol PinchRecognizerDelegate: AnyObject {
    /// `expanding` is true for a spread, false for a squeeze.
    func pinchDidStep(_ recognizer: PinchRecognizer, expanding: Bool)
    func pinchDidEnd(_ recognizer: PinchRecognizer)
}

/// Detects a three-finger pinch: index and middle together plus the thumb,
/// squeezed or spread.
///
/// Three contacts is what makes this safe to claim. macOS owns the two-finger
/// pinch for zoom, and its three-finger gestures are all swipes. A swipe moves
/// the whole hand while the spread between fingers stays roughly constant; a
/// pinch does the opposite. Comparing those two rates separates them cleanly and
/// without depending on how big anyone's hands are.
final class PinchRecognizer {

    weak var delegate: PinchRecognizerDelegate?

    /// Change in spread needed before the first step fires, mm.
    var activationDistance: Double = 8

    /// Further steps every this many mm in the same direction, so one squeeze
    /// skips one track and only a big deliberate one skips several.
    var repeatDistance: Double = 14

    /// Spread change per millimetre the hand travels. A real pinch scores around
    /// 1.5 to 2.5; a scroll anchored by a resting palm scores about 0.75,
    /// because the palm holds the centroid still while the fingers run away.
    var minSpreadPerTravel: Double = 1.1

    /// Absolute travel allowed while arming, mm. The twist has had one of these
    /// all along; the pinch did not, and the ratio alone let palm-anchored
    /// scrolls through. A pinch arrives within a few millimetres.
    var maxDriftWhileArming: Double = 9

    /// Spread settles faster than rotation does, and eating frames off the front
    /// of a quick pinch loses the movement that should have triggered it.
    var settlingFrames: Int = 1

    var idleTimeout: TimeInterval = 0.35

    private enum State {
        case idle
        case arming(accumulated: Double, frames: Int)
        case engaged(direction: Double, sinceStep: Double)
        case rejected
    }

    private var state: State = .idle
    private var watchdog: Timer?
    private var lastEventTime: TimeInterval = 0

    func handle(_ sample: TwistSample) {
        guard sample.contactCount == 3 else { return }

        switch sample.phase {
        case .began:
            state = .arming(accumulated: 0, frames: 0)
            armWatchdog()

        case .changed:
            switch state {
            case .rejected:
                break

            case .idle:
                state = .arming(accumulated: 0, frames: 0)

            case .arming(let accumulated, let frames):
                let next = frames + 1
                let total = next <= settlingFrames
                    ? accumulated
                    : accumulated + sample.spreadDeltaMM
                state = .arming(accumulated: total, frames: next)
                evaluateArming(total, sample)

            case .engaged(let direction, let sinceStep):
                // Only movement continuing the original direction counts, so
                // easing back does not creep towards another skip.
                let progressed = sinceStep + sample.spreadDeltaMM * direction
                if progressed >= repeatDistance {
                    state = .engaged(direction: direction, sinceStep: 0)
                    delegate?.pinchDidStep(self, expanding: direction > 0)
                } else {
                    state = .engaged(direction: direction, sinceStep: max(progressed, 0))
                }
            }
            armWatchdog()

        case .ended, .cancelled:
            reset()
        }
    }

    func abort() {
        reset()
    }

    private func evaluateArming(_ accumulated: Double, _ sample: TwistSample) {
        if sample.centroidDrift > maxDriftWhileArming {
            GestureLog.record(String(format: "pinch rejected: drift %.1fmm (max %.0f)",
                                     sample.centroidDrift, maxDriftWhileArming))
            state = .rejected
            return
        }

        guard abs(accumulated) >= activationDistance else { return }

        // Floor the divisor so a pinch that stays perfectly still does not
        // divide by something near zero.
        let rate = abs(accumulated) / max(sample.centroidDrift, 0.5)
        guard rate >= minSpreadPerTravel else {
            // Travelling far without changing spread much: a swipe, or a scroll
            // anchored by something that is not moving.
            GestureLog.record(String(format: "pinch rejected: rate %.2f (min %.2f) spread=%.1fmm drift=%.1fmm",
                                     rate, minSpreadPerTravel, accumulated, sample.centroidDrift))
            state = .rejected
            return
        }

        GestureLog.record(String(format: "pinch ENGAGED: spread=%.1fmm drift=%.1fmm rate=%.2f",
                                 accumulated, sample.centroidDrift, rate))
        let direction: Double = accumulated > 0 ? 1 : -1
        state = .engaged(direction: direction, sinceStep: 0)
        delegate?.pinchDidStep(self, expanding: direction > 0)
    }

    private func armWatchdog() {
        lastEventTime = ProcessInfo.processInfo.systemUptime
        guard watchdog == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if ProcessInfo.processInfo.systemUptime - self.lastEventTime > self.idleTimeout {
                self.reset()
            }
        }
        // Common modes: a default-mode timer stops while a menu is open, which
        // would strand the gesture holding input suppression open.
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func reset() {
        watchdog?.invalidate()
        watchdog = nil
        let wasEngaged: Bool
        if case .engaged = state { wasEngaged = true } else { wasEngaged = false }
        state = .idle
        if wasEngaged { delegate?.pinchDidEnd(self) }
    }
}
