import XCTest
@testable import HardlyWorking

/// Replays a scripted sequence of idle readings, so a test can describe what the
/// system reports before and after a nudge.
private final class FakeIdleMonitor: IdleMonitoring {
    private let readings: [TimeInterval]
    private(set) var callCount = 0

    init(_ readings: [TimeInterval]) {
        self.readings = readings
    }

    /// Lets a test observe that the counter was read at all, which is how the
    /// polling loop makes itself visible.
    var onRead: (() -> Void)?

    func idleSeconds() -> TimeInterval {
        defer { callCount += 1; onRead?() }
        guard !readings.isEmpty else { return 0 }
        return callCount < readings.count ? readings[callCount] : readings[readings.count - 1]
    }
}

private final class SpyJiggler: Jiggling {
    private(set) var jiggleCount = 0

    @discardableResult
    func jiggle() -> Bool {
        jiggleCount += 1
        return true
    }
}

/// Stands in for the case where the cursor position cannot be read: the jiggler
/// posts nothing at all and says so.
private final class FailingJiggler: Jiggling {
    private(set) var jiggleCount = 0

    @discardableResult
    func jiggle() -> Bool {
        jiggleCount += 1
        return false
    }
}

/// Reports one value until a test changes it, so a test can count reads without
/// its expectations depending on how many the implementation happens to make.
private final class ControllableIdleMonitor: IdleMonitoring {
    var seconds: TimeInterval
    private(set) var callCount = 0

    init(_ seconds: TimeInterval) {
        self.seconds = seconds
    }

    func idleSeconds() -> TimeInterval {
        callCount += 1
        return seconds
    }
}

private struct StubPermission: PermissionChecking {
    var isGranted: Bool
    func requestAccess() {}
    func openSettings() {}
}

private final class MutablePermission: PermissionChecking {
    var isGranted: Bool

    init(isGranted: Bool) {
        self.isGranted = isGranted
    }

    func requestAccess() {}
    func openSettings() {}
}

@MainActor
final class PresenceControllerTests: XCTestCase {
    private func makeSettings(enabled: Bool = true, threshold: Int = 240) -> Settings {
        let suite = "com.madzar.hardlyworking.tests.\(UUID().uuidString)"
        let settings = Settings(defaults: UserDefaults(suiteName: suite)!)
        settings.isEnabled = enabled
        settings.idleThresholdSeconds = threshold
        return settings
    }

    /// Hands back the doubles alongside the controller: without a reference to
    /// them no test could assert how many times the counter was read or the mouse
    /// moved, and an implementation reading one time too many would slip through.
    private func makeController(
        idle: [TimeInterval],
        permissionGranted: Bool = true,
        settings: Settings
    ) -> (controller: PresenceController, monitor: FakeIdleMonitor, jiggler: SpyJiggler) {
        let monitor = FakeIdleMonitor(idle)
        let jiggler = SpyJiggler()
        let controller = PresenceController(idleMonitor: monitor,
                                            jiggler: jiggler,
                                            permission: StubPermission(isGranted: permissionGranted),
                                            settings: settings,
                                            verificationDelay: .zero)
        return (controller, monitor, jiggler)
    }

    func testDoesNotJiggleBelowThreshold() async {
        let (controller, monitor, jiggler) = makeController(idle: [100], settings: makeSettings())

        await controller.tick()

        XCTAssertEqual(jiggler.jiggleCount, 0)
        XCTAssertEqual(controller.state, .active)
        XCTAssertEqual(monitor.callCount, 1, "Below the threshold: one reading, no verification.")
    }

    func testJigglesAboveThresholdAndStaysActiveWhenCounterDrops() async {
        let (controller, monitor, jiggler) = makeController(idle: [300, 0], settings: makeSettings())

        await controller.tick()

        XCTAssertEqual(jiggler.jiggleCount, 1)
        XCTAssertEqual(controller.state, .active)
        XCTAssertEqual(monitor.callCount, 2, "Exactly two readings: the decision, then the verification.")
    }

    func testFirstFailedVerificationDoesNotRaiseTheAlarmYet() async {
        let (controller, _, jiggler) = makeController(idle: [300, 300], settings: makeSettings())

        await controller.tick()

        XCTAssertEqual(jiggler.jiggleCount, 1)
        XCTAssertEqual(controller.state, .active, "An isolated miss must not raise the alarm.")
    }

    func testTwoConsecutiveFailedVerificationsRaiseTheAlarm() async {
        let (controller, _, jiggler) = makeController(idle: [300, 300, 300, 300], settings: makeSettings())

        await controller.tick()
        await controller.tick()

        XCTAssertEqual(jiggler.jiggleCount, 2)
        XCTAssertEqual(controller.state, .ineffective)
    }

    func testAlarmClearsBecauseAJiggleSucceeded() async {
        let (controller, _, jiggler) = makeController(idle: [300, 300, 300, 300, 300, 0],
                                                      settings: makeSettings())

        await controller.tick()
        await controller.tick()
        XCTAssertEqual(controller.state, .ineffective)

        await controller.tick()

        XCTAssertEqual(controller.state, .active, "An alarm must never stay stuck after a success.")
        XCTAssertEqual(jiggler.jiggleCount, 3,
                       "The alarm must clear BECAUSE a nudge worked, not because the user came back.")
    }

    func testPausedWhenDisabled() async {
        let (controller, _, jiggler) = makeController(idle: [300, 0], settings: makeSettings(enabled: false))

        await controller.tick()

        XCTAssertEqual(jiggler.jiggleCount, 0)
        XCTAssertEqual(controller.state, .paused)
    }

    func testNeedsPermissionWhenNotGranted() async {
        let (controller, _, jiggler) = makeController(idle: [300, 0],
                                                      permissionGranted: false,
                                                      settings: makeSettings())

        await controller.tick()

        XCTAssertEqual(jiggler.jiggleCount, 0, "Without permission, no movement may be attempted.")
        XCTAssertEqual(controller.state, .needsPermission)
    }

    func testRespectsCustomThreshold() async {
        let (controller, _, jiggler) = makeController(idle: [150, 0], settings: makeSettings(threshold: 120))

        await controller.tick()

        XCTAssertEqual(jiggler.jiggleCount, 1, "150s is past a threshold set to 120s.")
    }

    func testRefreshReportsPausedWhenDisabled() {
        let (controller, _, _) = makeController(idle: [300, 0], settings: makeSettings(enabled: false))

        controller.refresh()

        XCTAssertEqual(controller.state, .paused)
        controller.stop()
    }

    func testRefreshReportsNeedsPermissionWhenNotGranted() {
        let (controller, _, _) = makeController(idle: [300, 0],
                                                permissionGranted: false,
                                                settings: makeSettings())

        controller.refresh()

        XCTAssertEqual(controller.state, .needsPermission)
        controller.stop()
    }

    func testRefreshReportsActiveWhenEnabledAndPermitted() {
        let (controller, _, _) = makeController(idle: [300, 0], settings: makeSettings())

        controller.refresh()

        XCTAssertEqual(controller.state, .active)
        controller.stop()
    }

    func testStopReportsPausedSoTheIconNeverLies() {
        let (controller, _, _) = makeController(idle: [300, 0], settings: makeSettings())
        controller.refresh()
        XCTAssertEqual(controller.state, .active)

        controller.stop()

        XCTAssertEqual(controller.state, .paused,
                       "After stop(), the icon must never show 'active' above a dead loop.")
    }

    func testAlarmSurvivesASettingsChange() async {
        let settings = makeSettings()
        let (controller, _, _) = makeController(idle: [300, 300, 300, 300], settings: settings)
        await controller.tick()
        await controller.tick()
        XCTAssertEqual(controller.state, .ineffective)

        settings.idleThresholdSeconds = 300
        controller.refresh()

        XCTAssertEqual(controller.state, .ineffective,
                       "Changing a setting does not prove the fault is gone.")
        controller.stop()
    }

    func testAlarmSurvivesTurningTheAppOffAndOnAgain() async {
        let settings = makeSettings()
        let (controller, _, _) = makeController(idle: [300, 300, 300, 300], settings: settings)
        await controller.tick()
        await controller.tick()
        XCTAssertEqual(controller.state, .ineffective)

        settings.isEnabled = false
        controller.refresh()
        XCTAssertEqual(controller.state, .paused)

        settings.isEnabled = true
        controller.refresh()

        XCTAssertEqual(controller.state, .ineffective,
                       "Switching off and back on does not prove the fault is gone.")
        controller.stop()
    }

    func testAnIsolatedFailureAfterASuccessDoesNotRaiseTheAlarm() async {
        let (controller, _, _) = makeController(idle: [300, 300, 300, 300, 300, 0, 300, 300],
                                                settings: makeSettings())
        await controller.tick()
        await controller.tick()
        XCTAssertEqual(controller.state, .ineffective)

        await controller.tick()
        XCTAssertEqual(controller.state, .active)

        await controller.tick()

        XCTAssertEqual(controller.state, .active,
                       "After a success the count restarts, so an isolated miss does not re-alarm.")
    }

    func testAlarmSurvivesTheUserComingBack() async {
        let (controller, _, _) = makeController(idle: [300, 300, 300, 300, 100],
                                                settings: makeSettings())
        await controller.tick()
        await controller.tick()
        XCTAssertEqual(controller.state, .ineffective)

        await controller.tick()

        XCTAssertEqual(controller.state, .ineffective,
                       "The user coming back does not prove the fault is gone.")
    }

    func testRecoversOncePermissionIsGranted() async {
        let permission = MutablePermission(isGranted: false)
        let jiggler = SpyJiggler()
        let controller = PresenceController(idleMonitor: FakeIdleMonitor([300, 0]),
                                            jiggler: jiggler,
                                            permission: permission,
                                            settings: makeSettings(),
                                            verificationDelay: .zero)

        await controller.tick()
        XCTAssertEqual(controller.state, .needsPermission)
        XCTAssertEqual(jiggler.jiggleCount, 0)

        permission.isGranted = true
        await controller.tick()

        XCTAssertEqual(controller.state, .active,
                       "The app must recover on its own as soon as the permission is granted.")
        XCTAssertEqual(jiggler.jiggleCount, 1)
    }

    func testDetectsAFailedVerificationAtANonDefaultThreshold() async {
        let (controller, _, _) = makeController(idle: [300, 150, 300, 150],
                                                settings: makeSettings(threshold: 120))

        await controller.tick()
        await controller.tick()

        XCTAssertEqual(controller.state, .ineffective,
                       "Verification must compare against the configured threshold, not a hard-coded one.")
    }

    func testDoesNotJiggleBelowATenMinuteThreshold() async {
        let (controller, _, jiggler) = makeController(idle: [590, 0],
                                                      settings: makeSettings(threshold: 600))

        await controller.tick()

        XCTAssertEqual(jiggler.jiggleCount, 0,
                       "590s is below a threshold set to 600s; a hard-coded 120 would act here.")
    }

    /// A nudge that was never posted must not be followed by a verification read.
    /// The counter can fall for a reason of its own - the user coming back - and
    /// crediting that would clear an alert on someone else's evidence.
    func testANudgeThatWasNeverPostedIsNotVerifiedOrCredited() async {
        let monitor = ControllableIdleMonitor(300)
        let jiggler = FailingJiggler()
        let controller = PresenceController(idleMonitor: monitor,
                                            jiggler: jiggler,
                                            permission: StubPermission(isGranted: true),
                                            settings: makeSettings(),
                                            verificationDelay: .zero)

        await controller.tick()

        XCTAssertEqual(jiggler.jiggleCount, 1)
        XCTAssertEqual(monitor.callCount, 1,
                       "Nothing was posted, so there is no verification to read back.")

        await controller.tick()

        XCTAssertEqual(controller.state, .ineffective,
                       "Two nudges that never left the machine must raise the alert.")
    }

    /// `isRunning` only proves a Timer object exists. Firing it proves it was put
    /// on a run loop - a version that built one without scheduling it once shipped.
    func testRefreshPutsTheLoopOnTheRunLoopSoItActuallyFires() async {
        let monitor = FakeIdleMonitor([0])
        let controller = PresenceController(idleMonitor: monitor,
                                            jiggler: SpyJiggler(),
                                            permission: StubPermission(isGranted: true),
                                            settings: makeSettings(),
                                            verificationDelay: .zero,
                                            checkInterval: 0.01)

        let polled = expectation(description: "the loop reads the idle counter on its own")
        polled.assertForOverFulfill = false
        monitor.onRead = { polled.fulfill() }

        controller.refresh()
        // Awaiting frees the main actor, which the timer's Task needs to run.
        await fulfillment(of: [polled], timeout: 2)
        controller.stop()

        XCTAssertGreaterThan(monitor.callCount, 0,
                             "An unscheduled Timer never fires, so the counter would never be read again.")
    }

    func testRefreshArmsTheLoopEvenWithoutPermission() {
        let (controller, _, _) = makeController(idle: [300, 0],
                                                permissionGranted: false,
                                                settings: makeSettings())

        controller.refresh()

        XCTAssertEqual(controller.state, .needsPermission)
        XCTAssertTrue(controller.isRunning,
                      "The loop must run even without permission: it is what detects the grant.")

        controller.stop()

        XCTAssertFalse(controller.isRunning)
    }
}
