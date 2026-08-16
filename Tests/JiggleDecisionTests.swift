import XCTest
@testable import HardlyWorking

final class JiggleDecisionTests: XCTestCase {
    func testDoesNotJiggleBelowThreshold() {
        XCTAssertFalse(JiggleDecision.shouldJiggle(idleSeconds: 239, thresholdSeconds: 240))
    }

    func testJigglesExactlyAtThreshold() {
        XCTAssertTrue(JiggleDecision.shouldJiggle(idleSeconds: 240, thresholdSeconds: 240))
    }

    func testJigglesAboveThreshold() {
        XCTAssertTrue(JiggleDecision.shouldJiggle(idleSeconds: 500, thresholdSeconds: 240))
    }

    func testDoesNotJiggleWhenFreshlyActive() {
        XCTAssertFalse(JiggleDecision.shouldJiggle(idleSeconds: 0, thresholdSeconds: 240))
    }

    func testHonoursThresholdParameterRatherThanADefault() {
        XCTAssertTrue(JiggleDecision.shouldJiggle(idleSeconds: 150, thresholdSeconds: 120))
        XCTAssertFalse(JiggleDecision.shouldJiggle(idleSeconds: 150, thresholdSeconds: 300))
    }
}
