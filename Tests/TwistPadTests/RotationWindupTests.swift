import XCTest
@testable import TwistPad

/// The volume is clamped to 0...1 but the rotation driving it is not, so an
/// unbounded accumulator banks degrees the range cannot express. Twisting past
/// full and then back used to do nothing until the overshoot had been unwound,
/// which is the "it won't go up, I have to twist down and up again" stall.
final class RotationWindupTests: XCTestCase {

    /// Clockwise is negative, so the default direction is -1 with a 70° sweep.
    private let sweep = 70.0
    private let up = -1.0

    private func clamp(_ degrees: Double, base: Float, direction: Double? = nil) -> Double {
        VolumeDial.clampedRotation(degrees,
                                   base: base,
                                   direction: direction ?? up,
                                   sweep: sweep)
    }

    private func volume(for degrees: Double, base: Float, direction: Double? = nil) -> Float {
        let held = clamp(degrees, base: base, direction: direction)
        let offset = Float((direction ?? up) * held / sweep)
        return min(max(base + offset, 0), 1)
    }

    func testRotationInsideTheRangeIsUntouched() {
        // Half a sweep up from the middle lands exactly where it should.
        XCTAssertEqual(clamp(-35, base: 0.5), -35, accuracy: 0.0001)
        XCTAssertEqual(volume(for: -35, base: 0.5), 1.0, accuracy: 0.0001)
    }

    func testOvershootPastFullIsNotBanked() {
        // 35° reaches full from the middle. 300° must be held at that same 35,
        // not remembered.
        XCTAssertEqual(clamp(-300, base: 0.5), -35, accuracy: 0.0001)
    }

    func testOvershootPastSilentIsNotBanked() {
        XCTAssertEqual(clamp(300, base: 0.5), 35, accuracy: 0.0001)
    }

    func testComingBackDownWorksImmediatelyAfterOvershooting() {
        // The bug, in one test. Twist far past full, then reverse by one detent's
        // worth of a 16-step range. Without the clamp the volume would not move
        // until 265° had been given back.
        var accumulated = clamp(-300, base: 0.5)
        accumulated = clamp(accumulated + (sweep / 16), base: 0.5)
        XCTAssertLessThan(volume(for: accumulated, base: 0.5), 1.0)
        XCTAssertEqual(volume(for: accumulated, base: 0.5), 15.0 / 16, accuracy: 0.001)
    }

    func testTheClampFollowsTheBaseItStartedFrom() {
        // Near the top there is very little room left to give, and near the
        // bottom almost all of it.
        XCTAssertEqual(clamp(-300, base: 0.9), -7, accuracy: 0.0001)
        XCTAssertEqual(clamp(-300, base: 0.1), -63, accuracy: 0.0001)
    }

    func testReversedDirectionClampsTheSameWay() {
        let down = 1.0
        XCTAssertEqual(clamp(300, base: 0.5, direction: down), 35, accuracy: 0.0001)
        XCTAssertEqual(volume(for: 300, base: 0.5, direction: down), 1.0, accuracy: 0.0001)
        XCTAssertEqual(volume(for: -300, base: 0.5, direction: down), 0.0, accuracy: 0.0001)
    }

    func testAlreadyAtTheLimitLeavesNoHeadroom() {
        XCTAssertEqual(clamp(-300, base: 1.0), 0, accuracy: 0.0001)
        XCTAssertEqual(clamp(300, base: 0.0), 0, accuracy: 0.0001)
        // ...but the whole sweep is still available the other way.
        XCTAssertEqual(clamp(300, base: 1.0), 70, accuracy: 0.0001)
    }
}
