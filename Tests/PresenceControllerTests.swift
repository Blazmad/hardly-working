import XCTest
@testable import HardlyWorking

/// Renvoie une suite de valeurs scriptées, pour simuler le compteur
/// d'inactivité avant et après un mouvement de souris.
private final class FakeIdleMonitor: IdleMonitoring {
    private let values: [TimeInterval]
    private(set) var callCount = 0

    init(_ values: [TimeInterval]) { self.values = values }

    func idleSeconds() -> TimeInterval {
        defer { callCount += 1 }
        guard !values.isEmpty else { return 0 }
        return callCount < values.count ? values[callCount] : values[values.count - 1]
    }
}

private final class SpyJiggler: Jiggling {
    private(set) var jiggleCount = 0
    func jiggle() { jiggleCount += 1 }
}

private struct StubPermission: PermissionChecking {
    var isGranted: Bool
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

    private func makeController(
        idle: [TimeInterval],
        jiggler: SpyJiggler = SpyJiggler(),
        permissionGranted: Bool = true,
        settings: Settings
    ) -> PresenceController {
        PresenceController(
            idleMonitor: FakeIdleMonitor(idle),
            jiggler: jiggler,
            permission: StubPermission(isGranted: permissionGranted),
            settings: settings
        )
    }

    func testDoesNotJiggleBelowThreshold() {
        let jiggler = SpyJiggler()
        let controller = makeController(idle: [100], jiggler: jiggler, settings: makeSettings())
        controller.tick()
        XCTAssertEqual(jiggler.jiggleCount, 0)
        XCTAssertEqual(controller.state, .active)
    }

    func testJigglesAboveThresholdAndStaysActiveWhenCounterDrops() {
        let jiggler = SpyJiggler()
        // 1re lecture : inactif depuis 300s → on bouge. 2e lecture (vérification) : 0s → succès.
        let controller = makeController(idle: [300, 0], jiggler: jiggler, settings: makeSettings())
        controller.tick()
        XCTAssertEqual(jiggler.jiggleCount, 1)
        XCTAssertEqual(controller.state, .active)
    }

    func testReportsIneffectiveWhenCounterDoesNotDrop() {
        let jiggler = SpyJiggler()
        // Le mouvement est émis mais le compteur ne bouge pas : panne silencieuse détectée.
        let controller = makeController(idle: [300, 300], jiggler: jiggler, settings: makeSettings())
        controller.tick()
        XCTAssertEqual(jiggler.jiggleCount, 1)
        XCTAssertEqual(controller.state, .ineffective)
    }

    func testIneffectiveStateClearsOnNextSuccess() {
        let jiggler = SpyJiggler()
        // tick 1 : 300 puis 300 → ineffective. tick 2 : 300 puis 0 → retour à active.
        let controller = makeController(idle: [300, 300, 300, 0], jiggler: jiggler, settings: makeSettings())
        controller.tick()
        XCTAssertEqual(controller.state, .ineffective)
        controller.tick()
        XCTAssertEqual(controller.state, .active, "Une alerte ne doit jamais rester collée après un succès.")
    }

    func testPausedWhenDisabled() {
        let jiggler = SpyJiggler()
        let controller = makeController(idle: [300, 0], jiggler: jiggler, settings: makeSettings(enabled: false))
        controller.tick()
        XCTAssertEqual(jiggler.jiggleCount, 0)
        XCTAssertEqual(controller.state, .paused)
    }

    func testNeedsPermissionWhenNotGranted() {
        let jiggler = SpyJiggler()
        let controller = makeController(idle: [300, 0], jiggler: jiggler,
                                        permissionGranted: false, settings: makeSettings())
        controller.tick()
        XCTAssertEqual(jiggler.jiggleCount, 0, "Sans permission, aucun mouvement ne doit être tenté.")
        XCTAssertEqual(controller.state, .needsPermission)
    }

    func testRespectsCustomThreshold() {
        let jiggler = SpyJiggler()
        let controller = makeController(idle: [150, 0], jiggler: jiggler,
                                        settings: makeSettings(threshold: 120))
        controller.tick()
        XCTAssertEqual(jiggler.jiggleCount, 1, "150s dépasse un seuil réglé à 120s.")
    }
}
