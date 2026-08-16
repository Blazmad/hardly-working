import Foundation

enum PresenceState: Equatable {
    case paused
    case active
    case needsPermission
    case ineffective
}

/// Counts consecutive failed verifications so a raised alert can only be cleared
/// by evidence. It deliberately offers no general-purpose reset: the only ways
/// out are a nudge that worked, or a missing permission that explains the fault.
private struct FailureLedger {
    private static let failuresBeforeAlert = 2

    private var consecutiveFailures = 0

    var alertIsRaised: Bool { consecutiveFailures >= Self.failuresBeforeAlert }

    mutating func recordFailedNudge() {
        consecutiveFailures += 1
    }

    mutating func recordSuccessfulNudge() {
        consecutiveFailures = 0
    }

    mutating func forgetBecausePermissionIsMissing() {
        consecutiveFailures = 0
    }
}

@MainActor
final class PresenceController: ObservableObject {
    private static let checkInterval: TimeInterval = 20

    /// A synthetic mouse event takes a few milliseconds to reach the system idle
    /// counter. Measured by `spikes/settling-time.swift`: reading the counter back
    /// immediately sees the movement 2 times out of 12, and 12 out of 12 from 5 ms
    /// onwards. 50 ms keeps a wide margin while staying imperceptible.
    nonisolated static let defaultVerificationDelay: Duration = .milliseconds(50)

    @Published private(set) var state: PresenceState = .paused

    /// Lets tests assert that `refresh()` actually scheduled the timer. A version
    /// that built one without scheduling it once shipped unnoticed.
    var isRunning: Bool { timer != nil }

    private let idleMonitor: IdleMonitoring
    private let jiggler: Jiggling
    private let permission: PermissionChecking
    private let settings: Settings
    private let verificationDelay: Duration

    private var timer: Timer?
    private var failures = FailureLedger()

    init(idleMonitor: IdleMonitoring,
         jiggler: Jiggling,
         permission: PermissionChecking,
         settings: Settings,
         verificationDelay: Duration = PresenceController.defaultVerificationDelay) {
        self.idleMonitor = idleMonitor
        self.jiggler = jiggler
        self.permission = permission
        self.settings = settings
        self.verificationDelay = verificationDelay
    }

    func refresh() {
        stop()
        guard settings.isEnabled else { return }
        state = stateForFreshLoop()
        schedulePollingLoop()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        state = .paused
    }

    func tick() async {
        guard settings.isEnabled else {
            stop()
            return
        }
        guard permission.isGranted else {
            reportMissingPermission()
            return
        }
        guard userHasBeenIdleLongEnough() else {
            reportMonitoringState()
            return
        }
        await nudgeAndVerify()
    }
}

private extension PresenceController {
    func stateForFreshLoop() -> PresenceState {
        guard permission.isGranted else {
            failures.forgetBecausePermissionIsMissing()
            return .needsPermission
        }
        return failures.alertIsRaised ? .ineffective : .active
    }

    /// Scheduled in `.common` mode so the loop keeps firing while the user holds
    /// the menu bar menu open.
    func schedulePollingLoop() {
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Leaves the loop running on purpose: polling is the only way to notice the
    /// user granting the permission in System Settings.
    func reportMissingPermission() {
        failures.forgetBecausePermissionIsMissing()
        state = .needsPermission
    }

    func reportMonitoringState() {
        state = failures.alertIsRaised ? .ineffective : .active
    }

    func userHasBeenIdleLongEnough() -> Bool {
        JiggleDecision.shouldJiggle(idleSeconds: idleMonitor.idleSeconds(),
                                    thresholdSeconds: settings.idleThresholdSeconds)
    }

    func nudgeAndVerify() async {
        jiggler.jiggle()
        await waitForTheSystemToRegisterTheNudge()

        if nudgeResetTheIdleCounter() {
            failures.recordSuccessfulNudge()
        } else {
            failures.recordFailedNudge()
        }
        reportMonitoringState()
    }

    func waitForTheSystemToRegisterTheNudge() async {
        guard verificationDelay > .zero else { return }
        try? await Task.sleep(for: verificationDelay)
    }

    func nudgeResetTheIdleCounter() -> Bool {
        idleMonitor.idleSeconds() < TimeInterval(settings.idleThresholdSeconds)
    }
}
