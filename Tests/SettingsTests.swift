import XCTest
@testable import HardlyWorking

final class SettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.madzar.hardlyworking.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
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

    func testOfferedThresholdsIncludeTheDefault() {
        XCTAssertTrue(Settings.availableThresholds.contains(240))
        XCTAssertEqual(Settings.availableThresholds, [120, 180, 240, 300, 600])
    }
}
