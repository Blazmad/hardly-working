import XCTest
@testable import HardlyWorking

final class SettingsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = InMemoryDefaults()
    }

    func testDefaultsAreEnabledAtFourMinutes() {
        let settings = Settings(defaults: defaults)

        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.idleThresholdSeconds, 240)
    }

    func testChangesArePersisted() {
        let settings = Settings(defaults: defaults)
        settings.isEnabled = false
        settings.idleThresholdSeconds = 600

        let reloaded = Settings(defaults: defaults)

        XCTAssertFalse(reloaded.isEnabled)
        XCTAssertEqual(reloaded.idleThresholdSeconds, 600)
    }

    func testInvalidPersistedThresholdFallsBackToDefault() {
        for invalid in [0, -60, 61, 7_200] {
            defaults.set(invalid, forKey: "idleThresholdSeconds")

            let settings = Settings(defaults: defaults)

            XCTAssertEqual(settings.idleThresholdSeconds, 240,
                           "persisted \(invalid) must not reach the timer")
        }
    }

    func testInvalidPersistedThresholdIsHealedInTheStore() {
        defaults.set(0, forKey: "idleThresholdSeconds")

        _ = Settings(defaults: defaults)

        XCTAssertEqual(defaults.integer(forKey: "idleThresholdSeconds"), 240)
    }

    func testOfferedThresholdsIncludeTheDefault() {
        XCTAssertTrue(Settings.availableThresholds.contains(240))
        XCTAssertEqual(Settings.availableThresholds, [120, 180, 240, 300, 600])
    }
}
