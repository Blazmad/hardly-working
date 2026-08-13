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

    /// Renvoie le contrôleur ET ses doublures : sans référence sur elles, aucun
    /// test ne pourrait vérifier COMBIEN de fois le compteur a été lu ni la souris
    /// bougée — et une implémentation qui lirait une fois de trop passerait inaperçue.
    private func makeController(
        idle: [TimeInterval],
        permissionGranted: Bool = true,
        settings: Settings
    ) -> (controller: PresenceController, monitor: FakeIdleMonitor, jiggler: SpyJiggler) {
        let monitor = FakeIdleMonitor(idle)
        let jiggler = SpyJiggler()
        let controller = PresenceController(
            idleMonitor: monitor,
            jiggler: jiggler,
            permission: StubPermission(isGranted: permissionGranted),
            settings: settings,
            // Aucune attente en test : le délai d'installation ne concerne que
            // le vrai système, et le fake répond instantanément.
            verificationDelay: .zero
        )
        return (controller, monitor, jiggler)
    }

    func testDoesNotJiggleBelowThreshold() async {
        let (controller, monitor, jiggler) = makeController(idle: [100], settings: makeSettings())
        await controller.tick()
        XCTAssertEqual(jiggler.jiggleCount, 0)
        XCTAssertEqual(controller.state, .active)
        XCTAssertEqual(monitor.callCount, 1, "Sous le seuil : une seule lecture, pas de vérification.")
    }

    func testJigglesAboveThresholdAndStaysActiveWhenCounterDrops() async {
        // 1re lecture : inactif depuis 300s → on bouge. 2e lecture (vérification) : 0s → succès.
        let (controller, monitor, jiggler) = makeController(idle: [300, 0], settings: makeSettings())
        await controller.tick()
        XCTAssertEqual(jiggler.jiggleCount, 1)
        XCTAssertEqual(controller.state, .active)
        XCTAssertEqual(monitor.callCount, 2, "Exactement deux lectures : la décision, puis la vérification.")
    }

    func testFirstFailedVerificationDoesNotRaiseTheAlarmYet() async {
        // Un seul échec peut être un simple raté de propagation : on ne crie pas au loup.
        let (controller, _, jiggler) = makeController(idle: [300, 300], settings: makeSettings())
        await controller.tick()
        XCTAssertEqual(jiggler.jiggleCount, 1)
        XCTAssertEqual(controller.state, .active, "Un échec isolé ne doit pas déclencher l'alerte.")
    }

    func testTwoConsecutiveFailedVerificationsRaiseTheAlarm() async {
        // Deux échecs d'affilée : là, c'est une vraie panne.
        let (controller, _, jiggler) = makeController(idle: [300, 300, 300, 300], settings: makeSettings())
        await controller.tick()
        await controller.tick()
        XCTAssertEqual(jiggler.jiggleCount, 2)
        XCTAssertEqual(controller.state, .ineffective)
    }

    func testAlarmClearsBecauseAJiggleSucceeded() async {
        // ticks 1-2 : deux échecs → alerte. tick 3 : le mouvement fait effet → alerte levée.
        let (controller, _, jiggler) = makeController(idle: [300, 300, 300, 300, 300, 0],
                                                      settings: makeSettings())
        await controller.tick()
        await controller.tick()
        XCTAssertEqual(controller.state, .ineffective)

        await controller.tick()
        XCTAssertEqual(controller.state, .active, "Une alerte ne doit jamais rester collée après un succès.")
        XCTAssertEqual(jiggler.jiggleCount, 3,
                       "L'alerte doit se lever PARCE QU'un mouvement a réussi, pas parce que l'utilisateur est revenu.")
    }

    func testPausedWhenDisabled() async {
        let (controller, _, jiggler) = makeController(idle: [300, 0], settings: makeSettings(enabled: false))
        await controller.tick()
        XCTAssertEqual(jiggler.jiggleCount, 0)
        XCTAssertEqual(controller.state, .paused)
    }

    func testNeedsPermissionWhenNotGranted() async {
        let (controller, _, jiggler) = makeController(idle: [300, 0],
                                                      permissionGranted: false, settings: makeSettings())
        await controller.tick()
        XCTAssertEqual(jiggler.jiggleCount, 0, "Sans permission, aucun mouvement ne doit être tenté.")
        XCTAssertEqual(controller.state, .needsPermission)
    }

    func testRespectsCustomThreshold() async {
        let (controller, _, jiggler) = makeController(idle: [150, 0], settings: makeSettings(threshold: 120))
        await controller.tick()
        XCTAssertEqual(jiggler.jiggleCount, 1, "150s dépasse un seuil réglé à 120s.")
    }

    // MARK: - refresh() et stop()

    func testRefreshReportsPausedWhenDisabled() {
        let (controller, _, _) = makeController(idle: [300, 0], settings: makeSettings(enabled: false))
        controller.refresh()
        XCTAssertEqual(controller.state, .paused)
        controller.stop()
    }

    func testRefreshReportsNeedsPermissionWhenNotGranted() {
        let (controller, _, _) = makeController(idle: [300, 0],
                                                permissionGranted: false, settings: makeSettings())
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
                       "Après stop(), l'icône ne doit jamais afficher « actif » au-dessus d'une boucle morte.")
    }
}
