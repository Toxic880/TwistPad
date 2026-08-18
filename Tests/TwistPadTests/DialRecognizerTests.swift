import XCTest
@testable import TwistPad

/// Drives `DialRecognizer` with synthesised frames.
///
/// The numbers here come from the shapes the two gestures actually make. A twist
/// turns the fingers against each other and stays put, so its rotation travel is
/// large next to how far the midpoint moved. A scroll carries the pair across the
/// pad, so it is the other way round however many degrees it happens to pick up.
@MainActor
final class DialRecognizerTests: XCTestCase {

    private final class Spy: DialRecognizerDelegate {
        var engagements: [Double] = []
        var rotations: [Double] = []
        var disengagements = 0

        func dialDidEngage(_ recognizer: DialRecognizer, accumulated: Double) {
            engagements.append(accumulated)
        }
        func dial(_ recognizer: DialRecognizer, didRotateBy degrees: Double) {
            rotations.append(degrees)
        }
        func dialDidDisengage(_ recognizer: DialRecognizer) {
            disengagements += 1
        }
    }

    private var recognizer: DialRecognizer!
    private var spy: Spy!

    override func setUp() {
        super.setUp()
        recognizer = DialRecognizer()
        spy = Spy()
        recognizer.delegate = spy
    }

    // MARK: - Frame helpers

    private func sample(delta: Double = 0,
                        translation: Double = 0,
                        rotationTravel: Double = 4,
                        drift: Double? = nil,
                        separation: Double = 45,
                        phase: GesturePhase = .changed) -> TwistSample {
        TwistSample(deltaDegrees: delta,
                    centroidDrift: drift ?? translation,
                    translationMM: translation,
                    rotationTravelMM: rotationTravel,
                    initialSeparation: separation,
                    spreadDeltaMM: 0,
                    contactCount: 2,
                    phase: phase)
    }

    /// Feeds a touch-down plus `frames` identical frames.
    private func run(frames: Int,
                     delta: Double,
                     translation: Double,
                     rotationTravel: Double,
                     separation: Double = 45) {
        recognizer.handle(sample(separation: separation, phase: .began))
        for frame in 1...frames {
            // Both quantities grow with the gesture rather than appearing whole.
            let progress = Double(frame) / Double(frames)
            recognizer.handle(sample(delta: delta,
                                     translation: translation * progress,
                                     rotationTravel: rotationTravel * progress,
                                     separation: separation))
        }
    }

    // MARK: - Engaging

    func testDeliberateTwistEngages() {
        // Twelve frames of 2° each, pivoting in place: 24° of rotation for 3mm
        // of travel. The settling frames eat the first two.
        run(frames: 12, delta: 2, translation: 3, rotationTravel: 6)
        XCTAssertEqual(spy.engagements.count, 1)
    }

    func testRotationAfterEngagingIsPassedThroughUntouched() {
        run(frames: 12, delta: 2, translation: 3, rotationTravel: 6)
        XCTAssertFalse(spy.rotations.isEmpty)
        XCTAssertTrue(spy.rotations.allSatisfy { $0 == 2 })
    }

    func testEndingAnEngagedGestureDisengagesOnce() {
        run(frames: 12, delta: 2, translation: 3, rotationTravel: 6)
        recognizer.handle(sample(phase: .ended))
        XCTAssertEqual(spy.disengagements, 1)
    }

    // MARK: - Rejecting scrolls

    func testScrollThatRotatesPastTheThresholdIsRejected() {
        // The case that used to leak: a scroll picks up 24° of slip, but the pair
        // travelled 6mm together while only turning 1.5mm against each other.
        run(frames: 12, delta: 2, translation: 6, rotationTravel: 1.5, separation: 22)
        XCTAssertTrue(spy.engagements.isEmpty)
    }

    func testRejectionSticksForTheRestOfTheTouch() {
        run(frames: 12, delta: 2, translation: 6, rotationTravel: 1.5, separation: 22)
        // Keep turning, cleanly this time. The touch is already disqualified.
        for _ in 0..<20 {
            recognizer.handle(sample(delta: 4, translation: 1, rotationTravel: 8))
        }
        XCTAssertTrue(spy.engagements.isEmpty)
    }

    func testTravellingTooFarBeforeArmingIsRejected() {
        // Rotation builds slowly while the pair crosses the pad. The backstop is
        // checked every frame, so it fires before the threshold is ever reached
        // — and does not un-fire once the rotation starts looking convincing.
        recognizer.handle(sample(phase: .began))
        for frame in 1...14 {
            recognizer.handle(sample(delta: 0.5,
                                     translation: Double(frame),
                                     rotationTravel: Double(frame) * 3))
        }
        XCTAssertTrue(spy.engagements.isEmpty)
    }

    func testAnEngagedTwistIsAllowedToWander() {
        // The drift budget buys the right to take over. Once taken, a long twist
        // naturally travels, and pulling the rug there would be worse than the
        // occasional false positive it might have saved.
        run(frames: 12, delta: 2, translation: 3, rotationTravel: 6)
        XCTAssertEqual(spy.engagements.count, 1)
        for _ in 0..<20 {
            recognizer.handle(sample(delta: 2, translation: 30, rotationTravel: 6))
        }
        XCTAssertEqual(spy.disengagements, 0)
    }

    func testFingersPressedTogetherAreRejected() {
        run(frames: 12, delta: 2, translation: 1, rotationTravel: 6, separation: 8)
        XCTAssertTrue(spy.engagements.isEmpty)
    }

    func testHandsWiderThanATrackpadAreRejected() {
        run(frames: 12, delta: 2, translation: 1, rotationTravel: 6, separation: 130)
        XCTAssertTrue(spy.engagements.isEmpty)
    }

    // MARK: - Noise

    func testWobbleNeverAccumulatesIntoAnEngagement() {
        // Rotation that goes nowhere: the line jitters either side of where it
        // started, which is what settling contacts and scroll slip look like.
        recognizer.handle(sample(phase: .began))
        for frame in 0..<200 {
            recognizer.handle(sample(delta: frame.isMultiple(of: 2) ? 3 : -3,
                                     translation: 1,
                                     rotationTravel: 3))
        }
        XCTAssertTrue(spy.engagements.isEmpty)
    }

    func testRotationThatOnlyWanderedToTheThresholdIsRejected() {
        // Two forward, one back, over and over. It genuinely nets past 8° and no
        // single step back is big enough to count as a reversal, but two thirds
        // of the movement went the wrong way — which is a scroll slipping, not a
        // turn. Every frame stays well inside the drift budget so this can only
        // be caught by how incoherent the rotation is.
        recognizer.handle(sample(phase: .began))
        for frame in 0..<60 {
            recognizer.handle(sample(delta: frame.isMultiple(of: 2) ? 2 : -1,
                                     translation: 1,
                                     rotationTravel: 6))
        }
        XCTAssertTrue(spy.engagements.isEmpty)
    }

    func testRotationThatReversesRestartsRatherThanBanking() {
        // Nine degrees one way, then back again. Neither run reaches the
        // threshold on its own and the two must not add up to one that does.
        recognizer.handle(sample(phase: .began))
        for _ in 0..<6 { recognizer.handle(sample(delta: 1.5, translation: 1, rotationTravel: 6)) }
        for _ in 0..<6 { recognizer.handle(sample(delta: -1.5, translation: 1, rotationTravel: 6)) }
        XCTAssertTrue(spy.engagements.isEmpty)
    }

    func testAStallDoesNotLoseAnEngagedGesture() {
        run(frames: 12, delta: 2, translation: 3, rotationTravel: 6)
        XCTAssertEqual(spy.engagements.count, 1)
        // Fingers resting still, mid-twist. Zero-delta frames must not disengage.
        for _ in 0..<30 {
            recognizer.handle(sample(delta: 0, translation: 3, rotationTravel: 6))
        }
        XCTAssertEqual(spy.disengagements, 0)
    }

    // MARK: - Lifecycle

    func testANewTouchDownWhileEngagedReleasesTheOldOne() {
        run(frames: 12, delta: 2, translation: 3, rotationTravel: 6)
        recognizer.handle(sample(phase: .began))
        XCTAssertEqual(spy.disengagements, 1)
    }

    func testAbortReleasesAnEngagedGesture() {
        run(frames: 12, delta: 2, translation: 3, rotationTravel: 6)
        recognizer.abort()
        XCTAssertEqual(spy.disengagements, 1)
        XCTAssertFalse(recognizer.isEngaged)
    }

    func testEndingAGestureThatNeverEngagedDoesNotDisengage() {
        recognizer.handle(sample(phase: .began))
        recognizer.handle(sample(delta: 1, translation: 1, rotationTravel: 2))
        recognizer.handle(sample(phase: .ended))
        XCTAssertEqual(spy.disengagements, 0)
    }
}
