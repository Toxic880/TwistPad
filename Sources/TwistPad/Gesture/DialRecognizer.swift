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
    /// Furthest the midpoint between the fingers has been from where it landed,
    /// mm. A backstop: it only ever grows.
    let centroidDrift: Double
    /// How far the midpoint is from where it landed right now, mm.
    let translationMM: Double
    /// How far the contacts have moved *relative to that midpoint*, mm, averaged
    /// across them. This is the part of the movement that is the fingers turning
    /// against each other rather than the hand travelling.
    let rotationTravelMM: Double
    /// Distance between the contacts when they landed, mm. For three fingers
    /// this is the cluster spread on the same scale.
    let initialSeparation: Double
    /// Change in cluster spread since the last frame, mm. Negative is a pinch.
    let spreadDeltaMM: Double
    /// 2 for the volume gesture, 3 for track skipping.
    let contactCount: Int
    let phase: GesturePhase
}

protocol DialRecognizerDelegate: AnyObject {
    /// `accumulated` carries the arming rotation, whose sign is the direction.
    func dialDidEngage(_ recognizer: DialRecognizer, accumulated: Double)
    func dial(_ recognizer: DialRecognizer, didRotateBy degrees: Double)
    func dialDidDisengage(_ recognizer: DialRecognizer)
}

/// Decides when a multi-finger contact is a deliberate twist.
///
/// Distances are millimetres, never normalized trackpad units. The sensor is far
/// wider than it is deep, so the same physical gap measures about 1.6x larger
/// with the fingers stacked vertically than side by side. Gates written in
/// normalized units silently let vertical two-finger scrolls through.
///
/// A scroll does rotate a little, because two fingers never travel exactly
/// together, so rotation alone cannot separate the two. What actually separates
/// them is *what kind* of movement produced that rotation: a twist turns the
/// fingers against each other and goes nowhere, while a scroll carries the pair
/// across the pad and picks up a few degrees of slip on the way.
final class DialRecognizer {

    weak var delegate: DialRecognizerDelegate?

    /// Rotation required before the dial takes control, degrees. Spent arming
    /// rather than applied, so engaging feels like the free play at the start of
    /// a real knob.
    var activationThreshold: Double = 8

    /// The absolute backstop, mm. A twist pivots in place and has arrived within
    /// a few millimetres; a scroll has usually travelled 10mm or more by the time
    /// it has rotated this far. Stops applying once engaged, because a long twist
    /// naturally wanders.
    var maxDriftWhileArming: Double = 7

    /// How much of the fingers' travel has to be them turning against each other
    /// rather than moving as a unit — millimetres on both sides of the ratio.
    ///
    /// This is what the old degrees-per-millimetre rule was reaching for, and it
    /// never actually fired: it was only evaluated once rotation reached the
    /// activation threshold, which made it equivalent to a drift budget of
    /// `threshold / rate` mm — 8mm at the defaults, wider than the 7mm backstop
    /// that had already rejected the touch. Degrees also hid a stance
    /// dependency, since the same angle is a much smaller physical movement with
    /// the fingers close together than far apart. Comparing millimetres to
    /// millimetres removes both problems.
    var minRotationShare: Double = 0.4

    /// Fraction of the arming rotation that has to point the same way.
    ///
    /// Contacts shifting as they flatten under pressure, and the small slips
    /// inside a scroll, both wobble the line back and forth. Rotation that only
    /// reached the threshold by wandering there is not a turn, however much of
    /// it there is.
    ///
    /// Set well clear of both populations rather than between them. A wander
    /// scores about `1/sqrt(frames)` — a third or less over any realistic arming
    /// window — while a turn only drops near this if the sensor noise per frame
    /// rivals the rotation itself. The gap is wide, so there is nothing to buy
    /// by pushing it higher, and a real twist ignored is worse than one more
    /// touch left to the two millimetre-based gates.
    var minRotationCoherence: Double = 0.5

    /// Backing this far off the furthest point reached restarts the arming
    /// window, so a wobble cannot random-walk its way up to the threshold.
    var reversalTolerance: Double = 3

    /// Stance width, mm. Deliberately loose, and set below the narrowest twist
    /// actually measured rather than at it, because fitting a threshold to the
    /// edge of one session's data just moves the failures rather than removing
    /// them. This only rejects two fingers pressed together.
    var minSeparation: Double = 15
    var maxSeparation: Double = 115

    /// Contacts shift as they flatten out under pressure, which shows up as a
    /// few degrees of rotation that nobody intended. Ignore the settling frames.
    var settlingFrames: Int = 2

    /// Release if an engaged gesture goes quiet without an end phase. A dial
    /// stuck on is worse than one that lets go early.
    var idleTimeout: TimeInterval = 0.35

    /// Rotation accumulated while looking for the activation threshold.
    private struct Arming {
        var accumulated: Double = 0
        /// Rotation regardless of direction, for the coherence ratio.
        var gross: Double = 0
        /// Furthest `accumulated` has been, to notice a reversal.
        var peak: Double = 0
        var frames: Int = 0
    }

    private enum State {
        case idle
        case arming(Arming)
        case engaged
        /// Disqualified; ignore until the fingers lift.
        case rejected
    }

    private var state: State = .idle
    private var watchdog: Timer?
    private var lastEventTime: TimeInterval = 0

    // Per-gesture stats, purely for the opt-in log.
    private var peakAccumulated: Double = 0
    private var lastDrift: Double = 0
    private var lastSeparation: Double = 0
    private var lastShare: Double = 0
    private var lastCoherence: Double = 0
    private var outcome = "no rotation"

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
            peakAccumulated = 0
            lastDrift = 0
            lastShare = 0
            lastCoherence = 0
            lastSeparation = sample.initialSeparation
            let plausible = stanceIsPlausible(sample)
            outcome = plausible ? "no rotation" : "stance rejected"
            state = plausible ? .arming(Arming()) : .rejected
            armWatchdog()

        case .changed:
            switch state {
            case .rejected:
                break
            case .idle:
                state = stanceIsPlausible(sample) ? .arming(Arming()) : .rejected
            case .arming(let arming):
                let next = advance(arming, by: sample.deltaDegrees)
                state = .arming(next)
                evaluateArming(next, sample)
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

    private func advance(_ arming: Arming, by delta: Double) -> Arming {
        var next = arming
        next.frames += 1
        guard next.frames > settlingFrames else { return next }

        next.accumulated += delta
        next.gross += abs(delta)

        // Coming back on itself means whatever came before was not the start of
        // this turn. Count again from here rather than carrying a head start
        // nobody meant to give.
        let reversed = next.accumulated * next.peak < 0
            || abs(next.peak) - abs(next.accumulated) > reversalTolerance
        if reversed {
            return Arming(frames: next.frames)
        }
        if abs(next.accumulated) > abs(next.peak) { next.peak = next.accumulated }
        return next
    }

    private func evaluateArming(_ arming: Arming, _ sample: TwistSample) {
        if abs(arming.accumulated) > abs(peakAccumulated) { peakAccumulated = arming.accumulated }
        lastDrift = sample.centroidDrift
        lastSeparation = sample.initialSeparation
        lastShare = sample.rotationTravelMM / max(sample.translationMM, 0.5)
        lastCoherence = arming.gross > 0 ? abs(arming.accumulated) / arming.gross : 0

        if sample.centroidDrift > maxDriftWhileArming {
            state = .rejected
            outcome = "drift backstop"
            return
        }

        guard abs(arming.accumulated) >= activationThreshold else { return }

        let coherence = lastCoherence
        guard coherence >= minRotationCoherence else {
            // Got here by wandering rather than turning. Contact settling and
            // scroll slip both look like this, and neither becomes a twist, so
            // ignore the rest of this touch.
            state = .rejected
            outcome = String(format: "incoherent (%.2f, needs %.2f)",
                             coherence, minRotationCoherence)
            return
        }

        // Floor the divisor: a twist that pivots almost perfectly in place would
        // otherwise divide by something near zero.
        let share = lastShare
        guard share >= minRotationShare else {
            // Travelling rather than turning. Not a twist, and it will not
            // become one, so ignore the rest of this contact.
            state = .rejected
            outcome = String(format: "travelling not turning (%.2f, needs %.2f)",
                             share, minRotationShare)
            return
        }

        outcome = "ENGAGED"
        state = .engaged
        delegate?.dialDidEngage(self, accumulated: arming.accumulated)
    }

    /// One repeating timer for the life of the gesture, rather than a fresh
    /// one-shot per frame: contacts arrive at up to 120 Hz, and allocating and
    /// invalidating that many timers a second is pure waste.
    private func armWatchdog() {
        lastEventTime = ProcessInfo.processInfo.systemUptime
        guard watchdog == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if ProcessInfo.processInfo.systemUptime - self.lastEventTime > self.idleTimeout {
                self.reset(notify: true)
            }
        }
        // Common modes, not the default one: menu tracking and window resizing
        // both stop a default-mode timer, and those are exactly the moments when
        // a dial left stuck on would be hardest to get rid of.
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func reset(notify: Bool) {
        watchdog?.invalidate()
        watchdog = nil
        let wasEngaged = isEngaged
        if case .idle = state {} else {
            GestureLog.record(String(
                format: "end: %@  peak=%.1fdeg sep=%.1fmm drift=%.1fmm share=%.2f coherence=%.2f "
                      + "(needs %.0fdeg, sep %.0f-%.0f, share %.2f, coherence %.2f)",
                outcome, peakAccumulated, lastSeparation, lastDrift, lastShare, lastCoherence,
                activationThreshold, minSeparation, maxSeparation,
                minRotationShare, minRotationCoherence))
        }
        state = .idle
        if notify && wasEngaged {
            delegate?.dialDidDisengage(self)
        }
    }
}
