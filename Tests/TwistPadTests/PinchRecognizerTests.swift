import XCTest
@testable import TwistPad

/// A three-finger pinch has to be told apart from the system's three-finger
/// swipes. A swipe carries the hand while the spread between the fingers holds
/// roughly steady; a pinch changes the spread and goes nowhere.
@MainActor
final class PinchRecognizerTests: XCTestCase {

    private final class Spy: PinchRecognizerDelegate {
        var steps: [Bool] = []
        var ends = 0
        func pinchDidStep(_ recognizer: PinchRecognizer, expanding: Bool) {
            steps.append(expanding)
        }
        func pinchDidEnd(_ recognizer: PinchRecognizer) { ends += 1 }
    }

    private var recognizer: PinchRecognizer!
    private var spy: Spy!

    override func setUp() {
        super.setUp()
        recognizer = PinchRecognizer()
        spy = Spy()
        recognizer.delegate = spy
    }

    private func sample(spreadDelta: Double = 0,
                        drift: Double = 0,
                        phase: GesturePhase = .changed) -> TwistSample {
        TwistSample(deltaDegrees: 0,
                    centroidDrift: drift,
                    translationMM: drift,
                    rotationTravelMM: 0,
                    initialSeparation: 40,
                    spreadDeltaMM: spreadDelta,
                    contactCount: 3,
                    phase: phase)
    }

    func testSpreadingSkipsForward() {
        recognizer.handle(sample(phase: .began))
        for _ in 0..<8 { recognizer.handle(sample(spreadDelta: 2, drift: 1)) }
        XCTAssertEqual(spy.steps, [true])
    }

    func testSqueezingSkipsBack() {
        recognizer.handle(sample(phase: .began))
        for _ in 0..<8 { recognizer.handle(sample(spreadDelta: -2, drift: 1)) }
        XCTAssertEqual(spy.steps, [false])
    }

    func testKeepingGoingSkipsAgain() {
        recognizer.handle(sample(phase: .began))
        for _ in 0..<20 { recognizer.handle(sample(spreadDelta: 2, drift: 1)) }
        XCTAssertGreaterThan(spy.steps.count, 1)
        XCTAssertTrue(spy.steps.allSatisfy { $0 })
    }

    func testEasingBackDoesNotCreepTowardsAnotherSkip() {
        recognizer.handle(sample(phase: .began))
        for _ in 0..<8 { recognizer.handle(sample(spreadDelta: 2, drift: 1)) }
        XCTAssertEqual(spy.steps.count, 1)
        // Relax and re-open, repeatedly, without ever clearing the repeat
        // distance in one direction.
        for _ in 0..<20 {
            recognizer.handle(sample(spreadDelta: -3, drift: 1))
            recognizer.handle(sample(spreadDelta: 3, drift: 1))
        }
        XCTAssertEqual(spy.steps.count, 1)
    }

    func testAThreeFingerSwipeIsIgnored() {
        // The hand travels; the fingers keep their shape.
        recognizer.handle(sample(phase: .began))
        for frame in 1...15 {
            recognizer.handle(sample(spreadDelta: 0.7, drift: Double(frame)))
        }
        XCTAssertTrue(spy.steps.isEmpty)
    }

    func testTwoFingerSamplesAreNotItsBusiness() {
        let twoFingers = TwistSample(deltaDegrees: 0, centroidDrift: 0,
                                     translationMM: 0, rotationTravelMM: 0,
                                     initialSeparation: 40, spreadDeltaMM: 20,
                                     contactCount: 2, phase: .changed)
        recognizer.handle(twoFingers)
        XCTAssertTrue(spy.steps.isEmpty)
    }

    func testLiftingOffAfterASkipEndsTheGesture() {
        recognizer.handle(sample(phase: .began))
        for _ in 0..<8 { recognizer.handle(sample(spreadDelta: 2, drift: 1)) }
        recognizer.handle(sample(phase: .ended))
        XCTAssertEqual(spy.ends, 1)
    }
}
