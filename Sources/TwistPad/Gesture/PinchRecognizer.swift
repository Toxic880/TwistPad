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

    /// Spread change per millimetre the hand travels. Set low on purpose: in a
    /// real pinch only the thumb moves much, which drags the centroid by about a
    /// third of the thumb's travel, so a genuine pinch scores nearer 1.5 than
    /// infinity. A swipe still scores near zero because its spread barely
    /// changes, and the activation distance alone rejects most swipes anyway.
    var minSpreadPerTravel: Double = 0.45

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
        guard abs(accumulated) >= activationDistance else { return }

        // Floor the divisor so a pinch that stays perfectly still does not
        // divide by something near zero.
        let rate = abs(accumulated) / max(sample.centroidDrift, 0.5)
        guard rate >= minSpreadPerTravel else {
            // Travelling far without changing spread: that is a swipe.
            state = .rejected
            return
        }

        let direction: Double = accumulated > 0 ? 1 : -1
        state = .engaged(direction: direction, sinceStep: 0)
        delegate?.pinchDidStep(self, expanding: direction > 0)
    }

    private func armWatchdog() {
        lastEventTime = ProcessInfo.processInfo.systemUptime
        guard watchdog == nil else { return }
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if ProcessInfo.processInfo.systemUptime - self.lastEventTime > self.idleTimeout {
                self.reset()
            }
        }
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
